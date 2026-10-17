import Foundation
import Combine
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibrarySyncServiceTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testFailedMigrationPublishesOnlyToOwningService() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let other = LibrarySyncService()
        let initialState = sync.state
        var published: [LibrarySyncState] = []
        let observation = sync.$state.sink { published.append($0) }
        defer { observation.cancel() }

        do {
            try await sync.setEnabled(true, container.mainContext, drive: directory)
            XCTFail("An invalid iCloud Drive location must fail")
        } catch {
            XCTAssertNotNil(sync.state.lastError)
        }

        XCTAssertTrue(published.contains { $0.isSwitching })
        XCTAssertNotNil(published.last?.lastError)
        XCTAssertFalse(sync.state.isSwitching)
        XCTAssertNil(initialState.lastError)
        XCTAssertNil(other.state.lastError)
        XCTAssertFalse(other.state.isSwitching)
        XCTAssertNoThrow(try other.requireReady())
    }

    func testRenamedSyncedPDFCanBeOpenedWithoutLosingIdentityOrTags() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let data = Data("fixture".utf8)
        let original = try sync.savePDF(data, "Before.pdf", context)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let id = pdf.libraryID
        try PDFTagService.replaceTags(["Keep"], pdf, context, sync: sync)
        let renamed = original.deletingLastPathComponent().appendingPathComponent("After.pdf")
        try FileManager.default.moveItem(at: original, to: renamed)

        try await sync.download(pdf, context)
        await sync.refresh(context)
        try await sync.download(pdf, context)

        XCTAssertEqual(try pdf.resolveURL().standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(try Data(contentsOf: pdf.resolvedURL), data)
        XCTAssertEqual(pdf.libraryID, id)
        XCTAssertEqual(pdf.tags.map(\.name), ["Keep"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertNil(sync.state.lastError)
    }

    func testSyncedPDFWithoutBookmarkCanBeOpened() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let url = try sync.savePDF(Data("fixture".utf8), "Article.pdf", context)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        pdf.bookmarkData = nil
        try context.save()

        try await sync.download(pdf, context)

        XCTAssertNotNil(pdf.bookmarkData)
        XCTAssertEqual(try pdf.resolveURL().standardizedFileURL, url.standardizedFileURL)
    }

    func testRoundTripPreservesPDFTagsDatesAppearanceAndPreviousStorage() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let source = directory.appendingPathComponent("abcd.pdf")
        try Data("fixture".utf8).write(to: source)
        try PDFFileService.save(context, source, sync: sync)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let added = pdf.addedAt
        try PDFTagService.replaceTags(["Article", "Research"], pdf, context, sync: sync)
        try AppearanceSettingsService.save(context, .dark)
        try StorageSettingsService.saveFixedStorage(context, directory, sync: sync)
        let previousBookmark = try XCTUnwrap(LibrarySyncService.settings(context)?.fixedStorageBookmarkData)
        let drive = try makeDrive(directory)
        let cloud = drive.appendingPathComponent("websnapshot")

        try await sync.setEnabled(true, context, drive: drive)
        let id = try XCTUnwrap(pdf.libraryID)
        XCTAssertTrue(LibrarySyncService.isEnabled(context))
        XCTAssertEqual(StorageSettingsService.storage(try context.fetch(FetchDescriptor<StorageSettings>())), .fixed)
        XCTAssertEqual(pdf.addedAt, added)
        XCTAssertEqual(Set(pdf.tags.map(\.name)), ["Article", "Research"])
        XCTAssertTrue(pdf.url.path.hasPrefix(cloud.path + "/"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        let cloudPDF = pdf.url
        XCTAssertThrowsError(try StorageSettingsService.save(context, .flexibility, sync: sync))
        XCTAssertThrowsError(try StorageSettingsService.saveFixedStorage(context, directory, sync: sync))

        try await sync.setEnabled(false, context)
        XCTAssertFalse(LibrarySyncService.isEnabled(context))
        XCTAssertNil(pdf.syncRelativePath)
        XCTAssertEqual(pdf.url.deletingLastPathComponent().resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
        XCTAssertEqual(pdf.url.resolvingSymlinksInPath(), source.resolvingSymlinksInPath())
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("abcd 2.pdf").path))
        XCTAssertEqual(pdf.libraryID, id)
        XCTAssertEqual(pdf.addedAt, added)
        XCTAssertEqual(try Data(contentsOf: pdf.resolvedURL), Data("fixture".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloudPDF.path))
        let settings = try XCTUnwrap(LibrarySyncService.settings(context))
        XCTAssertEqual(settings.storage, .fixed)
        XCTAssertEqual(settings.fixedStoragePath.map { URL(fileURLWithPath: $0, isDirectory: true).resolvingSymlinksInPath() }, directory.resolvingSymlinksInPath())
        XCTAssertEqual(settings.fixedStorageBookmarkData, previousBookmark)
        XCTAssertNotNil(settings.syncDriveBookmarkData)
        XCTAssertEqual(settings.syncDrivePath, drive.path)
        XCTAssertEqual(try AppearanceSettingsService.load(context).appearance, .dark)

        try await sync.setEnabled(true, context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(pdf.libraryID, id)
        XCTAssertEqual(try SyncIndexStore(root: cloud).load().files.filter { !$0.isDeleted }.count, 1)
    }

    func testTwoDevicesMergeIndependentEditsAndDeletion() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drive = try makeDrive(directory)
        let first = try makeContainer()
        let second = try makeContainer()
        let firstSync = LibrarySyncService()
        let secondSync = LibrarySyncService()
        try await firstSync.setEnabled(true, first.mainContext, drive: drive)
        let url = try firstSync.savePDF(Data("fixture".utf8), "abcd.pdf", first.mainContext)
        await firstSync.refresh(first.mainContext)
        try await secondSync.setEnabled(true, second.mainContext, drive: drive)
        let a = try XCTUnwrap(first.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        let b = try XCTUnwrap(second.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(a.libraryID, b.libraryID)

        // Both devices edit before receiving the other's change.
        try PDFTagService.replaceTags(["A"], a, first.mainContext, sync: firstSync)
        try PDFTagService.replaceTags(["B"], b, second.mainContext, sync: secondSync)
        await firstSync.refresh(first.mainContext)
        await secondSync.refresh(second.mainContext)
        await firstSync.refresh(first.mainContext)
        XCTAssertEqual(Set(a.tags.map(\.name)), ["A", "B"])
        XCTAssertEqual(Set(b.tags.map(\.name)), ["A", "B"])

        try LibraryService.delete(first.mainContext, url, a.resolvedURL, sync: firstSync)
        await firstSync.refresh(first.mainContext)
        await secondSync.refresh(second.mainContext)
        XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try second.mainContext.fetchCount(FetchDescriptor<PDFTag>()), 0)
    }

    func testSaveEnforcesCloudDestinationEvenWithFlexibilityArgument() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let drive = try makeDrive(directory)
        let cloud = drive.appendingPathComponent("websnapshot")
        try await sync.setEnabled(true, container.mainContext, drive: drive)
        let url = try XCTUnwrap(WebCaptureService.save(PDFFileDocument(Data("fixture".utf8)), "New", nil,
                                                      container.mainContext, [], sync: sync) { _, _, _ in
            XCTFail("A synced save must never use the per-save destination picker")
            return nil
        })
        XCTAssertTrue(url.resolvingSymlinksInPath().path.hasPrefix(cloud.resolvingSymlinksInPath().path + "/"))
        XCTAssertNotNil(try LibrarySyncService.settings(container.mainContext)?.pendingSyncChanges)
        await sync.refresh(container.mainContext)
        XCTAssertNil(try LibrarySyncService.settings(container.mainContext)?.pendingSyncChanges)
        XCTAssertEqual(try SyncIndexStore(root: cloud).load().files.filter { !$0.isDeleted }.count, 1)
    }

    func testTurningSyncOffCopiesNewSavesToFixedFolderWithoutPrompting() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try StorageSettingsService.saveFixedStorage(context, directory, sync: sync)
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let cloudPDF = try sync.savePDF(Data("saved while syncing".utf8), "Saved.pdf", context)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try PDFTagService.replaceTags(["Keep"], pdf, context, sync: sync)
        let state = SettingsViewState()

        let succeeded = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in
            XCTFail("Fixed storage must use the saved folder without prompting")
            return nil
        }

        XCTAssertTrue(succeeded)
        XCTAssertNil(state.appError)
        XCTAssertFalse(LibrarySyncService.isEnabled(context))
        XCTAssertEqual(pdf.url.resolvingSymlinksInPath(), directory.appendingPathComponent("Saved.pdf").resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: pdf.resolveURL()), Data("saved while syncing".utf8))
        XCTAssertEqual(pdf.tags.map(\.name), ["Keep"])
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloudPDF.path))
        XCTAssertEqual(try LibrarySyncService.settings(context)?.storage, .fixed)
        XCTAssertNil(try LibrarySyncService.settings(context)?.pendingSyncChanges)

        let localURL = pdf.url
        let id = pdf.libraryID
        for _ in 0..<3 {
            try await sync.setEnabled(true, context)
            try await sync.setEnabled(false, context)
            XCTAssertEqual(pdf.url, localURL)
            XCTAssertEqual(pdf.libraryID, id)
            XCTAssertEqual(pdf.tags.map(\.name), ["Keep"])
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".pdf") }, ["Saved.pdf"])
    }

    func testTurningSyncOffAsksForFolderAndPreservesFlexibility() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let cloudPDF = try sync.savePDF(Data("fixture".utf8), "Saved.pdf", context)
        let state = SettingsViewState()
        let destination = directory.appendingPathComponent("selected", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var prompts = 0

        let succeeded = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in
            prompts += 1
            return destination
        }

        XCTAssertTrue(succeeded)
        XCTAssertEqual(prompts, 1)
        XCTAssertNil(state.appError)
        XCTAssertFalse(LibrarySyncService.isEnabled(context))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(pdf.url, destination.appendingPathComponent("Saved.pdf"))
        XCTAssertEqual(try Data(contentsOf: pdf.resolveURL()), Data("fixture".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloudPDF.path))
        XCTAssertEqual(try LibrarySyncService.settings(context)?.storage, .flexibility)
        XCTAssertNil(try LibrarySyncService.settings(context)?.fixedStorageBookmarkData)

        try await sync.setEnabled(true, context)
        let repeated = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in
            prompts += 1
            return destination
        }
        XCTAssertTrue(repeated)
        XCTAssertEqual(prompts, 2)
        XCTAssertEqual(pdf.url, destination.appendingPathComponent("Saved.pdf"))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["Saved.pdf"])
        XCTAssertEqual(try LibrarySyncService.settings(context)?.storage, .flexibility)

        var savePrompts = 0
        _ = try WebCaptureService.save(PDFFileDocument(Data("next".utf8)), "Next", nil, context, [], sync: sync) { _, _, _ in
            savePrompts += 1
            return nil
        }
        XCTAssertEqual(savePrompts, 1)
    }

    func testCancellingDestinationKeepsSyncSettingsAndPendingSave() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let cloudPDF = try sync.savePDF(Data("fixture".utf8), "Saved.pdf", context)
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        let pending = setting.pendingSyncChanges
        let state = SettingsViewState()

        let succeeded = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in nil }

        XCTAssertFalse(succeeded)
        XCTAssertNil(state.appError)
        XCTAssertTrue(setting.syncEnabled)
        XCTAssertEqual(setting.storage, .fixed)
        XCTAssertEqual(setting.previousStorageRawValue, StorageSettings.Storage.flexibility.rawValue)
        XCTAssertEqual(setting.pendingSyncChanges, pending)
        XCTAssertEqual(try context.fetch(FetchDescriptor<PDFFile>()).first?.url, cloudPDF)
        XCTAssertFalse(sync.state.isSwitching)
    }

    func testFixedWithoutFolderAsksAndRemembersChosenDestination() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try StorageSettingsService.save(context, .fixed, sync: sync)
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        _ = try sync.savePDF(Data("fixture".utf8), "Saved.pdf", context)
        let state = SettingsViewState()
        var prompts = 0

        let succeeded = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in
            prompts += 1
            return directory
        }

        XCTAssertTrue(succeeded)
        XCTAssertEqual(prompts, 1)
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        XCTAssertEqual(setting.storage, .fixed)
        XCTAssertEqual(setting.fixedStoragePath, directory.path)
        XCTAssertEqual(try StorageSettingsService.fixedStorageURL([setting], sync: sync)?.resolvingSymlinksInPath(), directory.resolvingSymlinksInPath())
        XCTAssertEqual(try context.fetch(FetchDescriptor<PDFFile>()).first?.url, directory.appendingPathComponent("Saved.pdf"))
    }

    func testInvalidDestinationKeepsSyncAndCloudPDF() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let cloudPDF = try sync.savePDF(Data("fixture".utf8), "Saved.pdf", context)
        let destination = directory.appendingPathComponent("not-a-folder")
        try Data("existing file".utf8).write(to: destination)
        let state = SettingsViewState()

        let succeeded = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in destination }

        XCTAssertFalse(succeeded)
        XCTAssertNotNil(state.appError)
        XCTAssertTrue(LibrarySyncService.isEnabled(context))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(pdf.url, cloudPDF)
        XCTAssertNotNil(pdf.syncRelativePath)
        XCTAssertEqual(try Data(contentsOf: cloudPDF), Data("fixture".utf8))
        XCTAssertEqual(try Data(contentsOf: destination), Data("existing file".utf8))
    }

    func testFailedEnableKeepsLocalModeAndOriginals() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let pdf = PDFFile(directory.appendingPathComponent("missing.pdf"))
        container.mainContext.insert(pdf)
        try container.mainContext.save()
        let drive = try makeDrive(directory)
        do {
            try await sync.setEnabled(true, container.mainContext,
                                                           drive: drive)
            XCTFail("Missing PDFs must not silently disappear during migration")
        } catch {}
        XCTAssertFalse(LibrarySyncService.isEnabled(container.mainContext))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertNil(pdf.syncRelativePath)
        XCTAssertFalse(sync.state.isSwitching)
    }

    func testFailedDisableKeepsSyncAndDoesNotRestoreStorageEarly() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let drive = try makeDrive(directory)
        let cloud = drive.appendingPathComponent("websnapshot")
        try await sync.setEnabled(true, context, drive: drive)
        let url = try sync.savePDF(Data("fixture".utf8), "abcd.pdf", context)
        await sync.refresh(context)
        try FileManager.default.removeItem(at: url)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(pdf.availability, .unavailable)
        try PDFFileService.deleteMissingFiles(context, [pdf], sync: sync)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        do {
            try await sync.setEnabled(false, context, localRoot: directory.appendingPathComponent("local"))
            XCTFail("Turning Sync off must finish copying every active PDF")
        } catch {}
        XCTAssertTrue(LibrarySyncService.isEnabled(context))
        XCTAssertEqual(try LibrarySyncService.settings(context)?.storage, .fixed)
        XCTAssertEqual(try LibrarySyncService.settings(context)?.fixedStoragePath, cloud.path)
        XCTAssertNotNil(pdf.syncRelativePath)
    }

    func testIncompleteRemoteRecordKeepsSyncUntilPDFCanBeCopied() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let drive = try makeDrive(directory)
        try await sync.setEnabled(true, context, drive: drive)
        let cloudPDF = try sync.savePDF(Data("fixture".utf8), "abcd.pdf", context)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        let pending = try SyncIndex.decode(XCTUnwrap(setting.pendingSyncChanges))
        var record = try XCTUnwrap(pending.files.first)
        let location = try XCTUnwrap(record.location)
        record.location = nil
        let store = SyncIndexStore(root: drive.appendingPathComponent("websnapshot"))
        try store.writeSnapshot(SyncIndex(files: [record]))
        setting.pendingSyncChanges = nil
        try context.save()
        let destination = directory.appendingPathComponent("local")

        do {
            try await sync.setEnabled(false, context, localRoot: destination)
            XCTFail("Turning Sync off must copy every cached active PDF")
        } catch {
            XCTAssertEqual(error as? SyncStoreError, .invalidIndex)
        }

        XCTAssertTrue(setting.syncEnabled)
        XCTAssertEqual(setting.storage, .fixed)
        XCTAssertEqual(pdf.url, cloudPDF)
        XCTAssertEqual(pdf.syncRelativePath, location.relativePath)
        XCTAssertEqual(try Data(contentsOf: cloudPDF), Data("fixture".utf8))

        record.location = location
        try store.publish(SyncIndex(files: [record]))
        try await sync.setEnabled(false, context, localRoot: destination)

        XCTAssertFalse(setting.syncEnabled)
        XCTAssertNil(pdf.syncRelativePath)
        XCTAssertEqual(pdf.url, destination.appendingPathComponent("abcd.pdf"))
        XCTAssertEqual(try Data(contentsOf: pdf.resolveURL()), Data("fixture".utf8))
        XCTAssertEqual(try Data(contentsOf: cloudPDF), Data("fixture".utf8))
    }

    func testOffLibraryKeepsExistingBehaviorAndDoesNotCreateCloudFiles() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let url = directory.appendingPathComponent("abcd.pdf")
        try Data("fixture".utf8).write(to: url)
        try PDFFileService.save(container.mainContext, url, sync: sync)
        let pdf = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        try PDFTagService.replaceTags(["Local"], pdf, container.mainContext, sync: sync)
        XCTAssertFalse(LibrarySyncService.isEnabled(container.mainContext))
        XCTAssertNil(pdf.syncRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
        try FileManager.default.removeItem(at: url)
        try PDFFileService.deleteMissingFiles(container.mainContext, [pdf], sync: sync)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 0)
    }

    func testReenableRecreatesRemovedFolderUsingPersistedDrivePermission() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let drive = try makeDrive(directory)
        let cloud = drive.appendingPathComponent("websnapshot")
        try await sync.setEnabled(true, context, drive: drive)
        _ = try sync.savePDF(Data("fixture".utf8), "abcd.pdf", context)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let id = pdf.libraryID
        try PDFTagService.replaceTags(["Keep"], pdf, context, sync: sync)
        try await sync.setEnabled(false, context, localRoot: directory.appendingPathComponent("local"))
        let bookmark = try XCTUnwrap(LibrarySyncService.settings(context)?.syncDriveBookmarkData)
        try FileManager.default.removeItem(at: cloud)

        // Use a new service, as after restarting the app. Only persisted settings
        // may supply the parent permission; no folder picker is involved.
        try await LibrarySyncService().setEnabled(true, context)

        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("index.json").path))
        XCTAssertEqual(pdf.libraryID, id)
        XCTAssertEqual(pdf.tags.map(\.name), ["Keep"])
        XCTAssertEqual(try Data(contentsOf: pdf.resolvedURL), Data("fixture".utf8))
        XCTAssertEqual(try LibrarySyncService.settings(context)?.syncFolderPath, cloud.path)
        XCTAssertNotNil(try LibrarySyncService.settings(context)?.syncDriveBookmarkData)
        XCTAssertFalse(bookmark.isEmpty)
    }

    func testReenableCreatesOriginalDestinationInsteadOfFollowingMovedFolder() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let drive = try makeDrive(directory)
        let cloud = drive.appendingPathComponent("websnapshot")
        try await sync.setEnabled(true, context, drive: drive)
        _ = try sync.savePDF(Data("fixture".utf8), "abcd.pdf", context)
        try await sync.setEnabled(false, context, localRoot: directory.appendingPathComponent("local"))
        let moved = directory.appendingPathComponent("moved/websnapshot")
        try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: cloud, to: moved)

        try await sync.setEnabled(true, context)

        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.appendingPathComponent("index.json").path))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertTrue(pdf.url.path.hasPrefix(cloud.path + "/"))
        XCTAssertEqual(try LibrarySyncService.settings(context)?.syncFolderPath, cloud.path)
    }

    func testReconnectRefreshesBookmarksWithoutChangingFilesOrSyncMode() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let drive = try makeDrive(directory)
        let folder = drive.appendingPathComponent("websnapshot", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent("Keep.pdf")
        let data = Data("Existing PDF".utf8)
        try data.write(to: url)
        let settings = StorageSettings(.fixed)
        settings.syncEnabled = true
        settings.syncDrivePath = drive.path
        settings.syncFolderPath = folder.path
        settings.fixedStoragePath = folder.path
        context.insert(settings)
        try context.save()

        try LibrarySyncService().reconnect(drive, context)

        let saved = try XCTUnwrap(LibrarySyncService.settings(ModelContext(container)))
        XCTAssertTrue(saved.syncEnabled)
        XCTAssertEqual(saved.storage, .fixed)
        XCTAssertEqual(saved.syncDrivePath, drive.path)
        XCTAssertEqual(saved.syncFolderPath, folder.path)
        XCTAssertNotNil(saved.syncDriveBookmarkData)
        XCTAssertNotNil(saved.syncFolderBookmarkData)
        XCTAssertEqual(saved.fixedStorageBookmarkData, saved.syncFolderBookmarkData)
        XCTAssertEqual(try Data(contentsOf: url), data)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path), ["Keep.pdf"])
    }

    func testReconnectRejectsAnotherDriveWithoutChangingSavedSettings() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let drive = try makeDrive(directory)
        let other = try makeDrive(directory.appendingPathComponent("Other", isDirectory: true))
        let settings = StorageSettings(.flexibility)
        settings.syncDrivePath = drive.path
        context.insert(settings)
        try context.save()

        XCTAssertThrowsError(try LibrarySyncService().reconnect(other, context)) {
            XCTAssertEqual($0 as? SyncStoreError, .wrongDrive)
        }

        let saved = try XCTUnwrap(LibrarySyncService.settings(ModelContext(container)))
        XCTAssertFalse(saved.syncEnabled)
        XCTAssertEqual(saved.storage, .flexibility)
        XCTAssertEqual(saved.syncDrivePath, drive.path)
        XCTAssertNil(saved.syncDriveBookmarkData)
        XCTAssertNil(saved.syncFolderBookmarkData)
    }

    private func makeDrive(_ directory: URL) throws -> URL {
        let drive = directory.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        return drive
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
        return container
    }

    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url.resolvingSymlinksInPath()
    }
}
