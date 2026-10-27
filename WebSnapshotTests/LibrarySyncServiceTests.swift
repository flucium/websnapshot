import CoreGraphics
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
        let original = try XCTUnwrap(LibraryService.savePDF(data, "Before.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let id = pdf.libraryID
        try LibraryService.replaceTags(["Keep"], pdf, context, sync: sync)
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
        let url = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Article.pdf", context, [], sync: sync))
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
        try LibraryService.registerPDF(context, source, sync: sync)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let added = pdf.addedAt
        try LibraryService.replaceTags(["Article", "Research"], pdf, context, sync: sync)
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
        let url = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "abcd.pdf", first.mainContext, [], sync: firstSync))
        await firstSync.refresh(first.mainContext)
        try await secondSync.setEnabled(true, second.mainContext, drive: drive)
        let a = try XCTUnwrap(first.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        let b = try XCTUnwrap(second.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(a.libraryID, b.libraryID)

        // Both devices edit before receiving the other's change.
        try LibraryService.replaceTags(["A"], a, first.mainContext, sync: firstSync)
        try LibraryService.replaceTags(["B"], b, second.mainContext, sync: secondSync)
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
        let url = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), URL.pdfFileName("New", nil),
                                                      container.mainContext, [], sync: sync) { _ in
            XCTFail("A synced save must never use the per-save destination picker")
            return nil
        })
        XCTAssertTrue(url.resolvingSymlinksInPath().path.hasPrefix(cloud.resolvingSymlinksInPath().path + "/"))
        XCTAssertNotNil(try LibrarySyncService.settings(container.mainContext)?.pendingSyncChanges)
        await sync.refresh(container.mainContext)
        XCTAssertNil(try LibrarySyncService.settings(container.mainContext)?.pendingSyncChanges)
        XCTAssertEqual(try SyncIndexStore(root: cloud).load().files.filter { !$0.isDeleted }.count, 1)
    }

    func testFailedSyncedSavePreservesExistingPDFAndPendingChanges() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let data = Data("original".utf8)
        let original = try XCTUnwrap(LibraryService.savePDF(data, "Original.pdf", context, [], sync: sync))
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        let pending = setting.pendingSyncChanges
        setting.syncCounter = Int64.max - 1
        try context.save()

        XCTAssertThrowsError(try LibraryService.savePDF(Data("replacement".utf8), "New.pdf", context, [], sync: sync))

        let stored = ModelContext(container)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try LibrarySyncService.settings(stored)?.pendingSyncChanges, pending)
        XCTAssertEqual(try Data(contentsOf: original), data)
        let root = try sync.folderURL(setting)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let pdfs = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "pdf" }
        XCTAssertEqual(pdfs, [original])
    }

    func testFailedTagChangePreservesTagsAndPendingChanges() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let url = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Article.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Original"], pdf, context, sync: sync)
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        let pending = setting.pendingSyncChanges
        let baseline = pdf.syncBaselineTags
        setting.syncCounter = Int64.max - 1
        try context.save()

        XCTAssertThrowsError(try LibraryService.replaceTags(["Replacement"], pdf, context, sync: sync))

        let stored = ModelContext(container)
        let savedPDF = try XCTUnwrap(stored.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(savedPDF.tags.map(\.name), ["Original"])
        XCTAssertEqual(savedPDF.syncBaselineTags, baseline)
        XCTAssertEqual(try LibrarySyncService.settings(stored)?.pendingSyncChanges, pending)
        XCTAssertEqual(try LibrarySyncService.settings(stored)?.syncCounter, Int64.max - 1)
        XCTAssertEqual(try Data(contentsOf: url), Data("fixture".utf8))
    }

    func testDeletingDuplicateSyncedEntriesQueuesEveryDeletion() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let url = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Article.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Keep"], pdf, context, sync: sync)
        let duplicate = PDFFile(url)
        duplicate.libraryID = UUID()
        duplicate.syncRelativePath = pdf.syncRelativePath
        duplicate.tags = pdf.tags
        context.insert(duplicate)
        try context.save()
        let ids = Set([try XCTUnwrap(pdf.libraryID), try XCTUnwrap(duplicate.libraryID)])

        try LibraryService.removePDFRecords(context, url, sync: sync)

        let stored = ModelContext(container)
        let pending = try XCTUnwrap(LibrarySyncService.settings(stored)?.pendingSyncChanges)
        XCTAssertEqual(Set(try SyncIndex.decode(pending).files.filter(\.isDeleted).map(\.id)), ids)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFTag>()), 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testFailedDeletionPreservesAllSyncedEntriesAndTheirFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let data = Data("fixture".utf8)
        let url = try XCTUnwrap(LibraryService.savePDF(data, "Article.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Keep"], pdf, context, sync: sync)
        let duplicate = PDFFile(url)
        duplicate.libraryID = UUID()
        duplicate.syncRelativePath = pdf.syncRelativePath
        duplicate.tags = pdf.tags
        context.insert(duplicate)
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        let pending = setting.pendingSyncChanges
        setting.syncCounter = Int64.max - 2
        try context.save()

        XCTAssertThrowsError(try LibraryService.removePDFRecords(context, url, sync: sync))

        let stored = ModelContext(container)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFFile>()), 2)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFTag>()), 1)
        XCTAssertEqual(try LibrarySyncService.settings(stored)?.pendingSyncChanges, pending)
        XCTAssertEqual(try LibrarySyncService.settings(stored)?.syncCounter, Int64.max - 2)
        XCTAssertEqual(try Data(contentsOf: url), data)
    }

    func testTurningSyncOffCopiesNewSavesToFixedFolderWithoutPrompting() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try StorageSettingsService.saveFixedStorage(context, directory, sync: sync)
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let cloudPDF = try XCTUnwrap(LibraryService.savePDF(Data("saved while syncing".utf8), "Saved.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Keep"], pdf, context, sync: sync)
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

    func testTurningSyncOffImportsFixedFolderPDFsAndPreservesTagsWithoutDuplicates() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixed = directory.appendingPathComponent("Fixed", isDirectory: true)
        try FileManager.default.createDirectory(at: fixed, withIntermediateDirectories: true)
        let container = try makeContainer()
        let context = container.mainContext
        let data = try makePDFData()
        let original = fixed.appendingPathComponent("Original.pdf")
        try data.write(to: original)
        try LibraryService.registerPDF(context, original, sync: sync)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let added = pdf.addedAt
        try LibraryService.replaceTags(["Article", "Research"], pdf, context, sync: sync)
        try StorageSettingsService.saveFixedStorage(context, fixed, sync: sync)
        let drive = try makeDrive(directory)
        try await sync.setEnabled(true, context, drive: drive)
        let cloudPDF = pdf.url
        let id = pdf.libraryID
        let imported = fixed.appendingPathComponent("Added.PDF")
        try data.write(to: imported)
        try data.write(to: fixed.appendingPathComponent(".Hidden.pdf"))
        try data.write(to: fixed.appendingPathComponent("Notes.txt"))
        try Data("invalid PDF".utf8).write(to: fixed.appendingPathComponent("Invalid.pdf"))
        try FileManager.default.createDirectory(at: fixed.appendingPathComponent("Folder.pdf"), withIntermediateDirectories: true)
        let outside = directory.appendingPathComponent("Outside.pdf")
        try data.write(to: outside)
        try FileManager.default.createSymbolicLink(at: fixed.appendingPathComponent("Linked.pdf"), withDestinationURL: outside)
        let state = SettingsViewState()

        let succeeded = await SettingsViewService.changeSync(state, context, false, sync: sync) { _, _, _ in
            XCTFail("Fixed storage must use the saved folder without prompting")
            return nil
        }

        XCTAssertTrue(succeeded)
        XCTAssertNil(state.appError)
        XCTAssertFalse(LibrarySyncService.isEnabled(context))
        let files = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(Set(files.map { $0.url.resolvingSymlinksInPath().standardizedFileURL }), Set([original, imported].map { $0.resolvingSymlinksInPath().standardizedFileURL }))
        XCTAssertEqual(pdf.libraryID, id)
        XCTAssertEqual(pdf.addedAt, added)
        XCTAssertEqual(Set(pdf.tags.map(\.name)), ["Article", "Research"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 2)
        XCTAssertEqual(try Data(contentsOf: cloudPDF), data)
        XCTAssertEqual(try Data(contentsOf: original), data)
        XCTAssertEqual(try Data(contentsOf: imported), data)
        let stored = ModelContext(container)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFFile>()), 2)
        XCTAssertEqual(try stored.fetchCount(FetchDescriptor<PDFTag>()), 2)

        try await sync.setEnabled(true, context)
        try await sync.setEnabled(false, context)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 2)
        XCTAssertEqual(Set(pdf.tags.map(\.name)), ["Article", "Research"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 2)
    }

    func testTurningSyncOffImportsConflictingFixedPDFWithoutOverwritingFilesOrTags() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let fixed = directory.appendingPathComponent("Fixed", isDirectory: true)
        try FileManager.default.createDirectory(at: fixed, withIntermediateDirectories: true)
        let container = try makeContainer()
        let context = container.mainContext
        try StorageSettingsService.saveFixedStorage(context, fixed, sync: sync)
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let data = try makePDFData()
        let cloudPDF = try XCTUnwrap(LibraryService.savePDF(data, "Article.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let id = pdf.libraryID
        try LibraryService.replaceTags(["Research"], pdf, context, sync: sync)
        let local = fixed.appendingPathComponent("Article.pdf")
        let localData = data + Data("\n% Local copy".utf8)
        try localData.write(to: local)

        try await sync.setEnabled(false, context)

        let files = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(files.count, 2)
        XCTAssertEqual(pdf.url.resolvingSymlinksInPath().standardizedFileURL, fixed.appendingPathComponent("Article 2.pdf").resolvingSymlinksInPath().standardizedFileURL)
        XCTAssertEqual(pdf.libraryID, id)
        XCTAssertEqual(pdf.tags.map(\.name), ["Research"])
        XCTAssertEqual(try Data(contentsOf: pdf.resolveURL()), data)
        XCTAssertEqual(try Data(contentsOf: cloudPDF), data)
        XCTAssertEqual(try Data(contentsOf: local), localData)
        let imported = try XCTUnwrap(files.first { $0.url.resolvingSymlinksInPath().standardizedFileURL == local.resolvingSymlinksInPath().standardizedFileURL })
        XCTAssertTrue(imported.tags.isEmpty)
        XCTAssertNil(imported.syncRelativePath)
    }

    func testTurningSyncOffDoesNotImportUnregisteredPDFsForFlexibility() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let destination = directory.appendingPathComponent("Selected", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let data = try makePDFData()
        let unrelated = destination.appendingPathComponent("Unrelated.pdf")
        try data.write(to: unrelated)
        _ = try XCTUnwrap(LibraryService.savePDF(data, "Synced.pdf", context, [], sync: sync))

        try await sync.setEnabled(false, context, localRoot: destination)

        XCTAssertEqual(try context.fetch(FetchDescriptor<PDFFile>()).map(\.url), [destination.appendingPathComponent("Synced.pdf")])
        XCTAssertEqual(try Data(contentsOf: unrelated), data)
        XCTAssertEqual(try LibrarySyncService.settings(context)?.storage, .flexibility)
    }

    func testTurningSyncOffAsksForFolderAndPreservesFlexibility() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: makeDrive(directory))
        let cloudPDF = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Saved.pdf", context, [], sync: sync))
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
        _ = try LibraryService.savePDF(Data("next".utf8), URL.pdfFileName("Next", nil), context, [], sync: sync) { _ in
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
        let cloudPDF = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Saved.pdf", context, [], sync: sync))
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
        _ = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Saved.pdf", context, [], sync: sync))
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
        let cloudPDF = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "Saved.pdf", context, [], sync: sync))
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
        let url = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "abcd.pdf", context, [], sync: sync))
        await sync.refresh(context)
        try FileManager.default.removeItem(at: url)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(pdf.availability, .unavailable)
        try LibraryService.deleteMissingFiles(context, [pdf], sync: sync)
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
        let cloudPDF = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "abcd.pdf", context, [], sync: sync))
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
        try LibraryService.registerPDF(container.mainContext, url, sync: sync)
        let pdf = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Local"], pdf, container.mainContext, sync: sync)
        XCTAssertFalse(LibrarySyncService.isEnabled(container.mainContext))
        XCTAssertNil(pdf.syncRelativePath)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
        try FileManager.default.removeItem(at: url)
        try LibraryService.deleteMissingFiles(container.mainContext, [pdf], sync: sync)
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
        _ = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "abcd.pdf", context, [], sync: sync))
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let id = pdf.libraryID
        try LibraryService.replaceTags(["Keep"], pdf, context, sync: sync)
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
        _ = try XCTUnwrap(LibraryService.savePDF(Data("fixture".utf8), "abcd.pdf", context, [], sync: sync))
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

    private func makePDFData() throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return data as Data
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
