import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryDeletionTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testDeletesRegisteredFilesAcrossFoldersAndAllTagsWhilePreservingSettings() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let otherDirectory = directory.appendingPathComponent("Other")
        try FileManager.default.createDirectory(at: otherDirectory, withIntermediateDirectories: true)
        let urls = [directory.appendingPathComponent("First.pdf"), otherDirectory.appendingPathComponent("Second.pdf")]
        let unrelated = directory.appendingPathComponent("Unregistered.pdf")
        try Data("keep".utf8).write(to: unrelated)
        let container = try makeContainer()
        let context = container.mainContext
        let storage = StorageSettings(.fixed)
        storage.fixedStoragePath = directory.path
        context.insert(storage)
        context.insert(AppearanceSettings(.dark))
        for url in urls {
            try Data("fixture".utf8).write(to: url)
            try LibraryService.registerPDF(context, url, sync: sync)
        }
        for pdf in try context.fetch(FetchDescriptor<PDFFile>()) {
            try LibraryService.replaceTags(["Shared"], pdf, context, sync: sync)
            pdf.searchableText = "cached content"
            pdf.contentFingerprint = "fingerprint"
        }
        let duplicate = PDFFile(urls[0])
        context.insert(duplicate)
        context.insert(PDFTag("Unused", normalizedName: "unused"))
        try context.save()

        try LibraryService.deleteAll(context, sync: sync)

        try assertEmpty(container)
        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        XCTAssertEqual(try Data(contentsOf: unrelated), Data("keep".utf8))
        let saved = ModelContext(container)
        XCTAssertEqual(try saved.fetch(FetchDescriptor<AppearanceSettings>()).first?.appearance, .dark)
        XCTAssertEqual(try saved.fetch(FetchDescriptor<StorageSettings>()).first?.fixedStoragePath, directory.path)
    }

    func testDeletesRenamedBookmarkedFilesAndRemovesMissingEntries() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Original.pdf")
        let renamed = directory.appendingPathComponent("Renamed.pdf")
        let missing = directory.appendingPathComponent("Missing.pdf")
        let container = try makeContainer()
        let context = container.mainContext
        for url in [original, missing] {
            try Data("fixture".utf8).write(to: url)
            try LibraryService.registerPDF(context, url, sync: sync)
        }
        try FileManager.default.moveItem(at: original, to: renamed)
        try FileManager.default.removeItem(at: missing)

        try LibraryService.deleteAll(context, sync: sync)

        try assertEmpty(container)
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
    }

    func testFileDeletionFailurePreservesTheFileAndItsTags() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Keep.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        let pdf = PDFFile(url)
        context.insert(pdf)
        try LibraryService.replaceTags(["Keep"], pdf, context, sync: sync)

        XCTAssertThrowsError(try LibraryService.deleteAll(context, sync: sync) { _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        let saved = ModelContext(container)
        XCTAssertEqual(try saved.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try saved.fetch(FetchDescriptor<PDFTag>()).first?.name, "Keep")
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testClearsOrphanedTagsWithoutFilesAndCanRunAgain() throws {
        let container = try makeContainer()
        container.mainContext.insert(PDFTag("Unused", normalizedName: "unused"))
        try container.mainContext.save()

        try LibraryService.deleteAll(container.mainContext, sync: sync)
        try LibraryService.deleteAll(container.mainContext, sync: sync)

        try assertEmpty(container)
    }

    func testSyncedDeletionRemovesEveryFileAndReachesAnotherDevice() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drive = directory.appendingPathComponent("Mobile Documents/com~apple~CloudDocs")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: drive)
        var urls: [URL] = []
        for name in ["First.pdf", "Second.pdf"] {
            urls.append(try XCTUnwrap(LibraryService.savePDF(Data(name.utf8), name, context, [], sync: sync)))
        }
        for pdf in try context.fetch(FetchDescriptor<PDFFile>()) {
            try LibraryService.replaceTags(["Shared"], pdf, context, sync: sync)
        }
        await sync.refresh(context)
        let other = try makeContainer()
        let otherSync = LibrarySyncService()
        try await otherSync.setEnabled(true, other.mainContext, drive: drive)
        XCTAssertEqual(try other.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 2)

        try LibraryService.deleteAll(context, sync: sync)

        try assertEmpty(container)
        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
        let setting = try XCTUnwrap(LibrarySyncService.settings(context))
        let pending = try LibrarySyncRepository.pendingChanges(setting)
        XCTAssertEqual(pending.files.filter(\.isDeleted).count, 2)
        await sync.refresh(context)
        await otherSync.refresh(other.mainContext)
        try assertEmpty(other)
        XCTAssertNil(sync.state.lastError)
        XCTAssertNil(otherSync.state.lastError)
        XCTAssertTrue(setting.syncEnabled)
    }

    func testFailedSyncedFileDeletionsAreAllQueuedAndRetriedWhenLibraryIsEmpty() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let drive = directory.appendingPathComponent("Mobile Documents/com~apple~CloudDocs")
        try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        let container = try makeContainer()
        let context = container.mainContext
        try await sync.setEnabled(true, context, drive: drive)
        var urls: [URL] = []
        for name in ["First.pdf", "Second.pdf"] {
            urls.append(try XCTUnwrap(LibraryService.savePDF(Data(name.utf8), name, context, [], sync: sync)))
        }

        XCTAssertThrowsError(try LibraryService.deleteAll(context, sync: sync) { _ in
            throw CocoaError(.fileWriteNoPermission)
        })

        let saved = ModelContext(container)
        saved.autosaveEnabled = false
        let setting = try XCTUnwrap(LibrarySyncService.settings(saved))
        let paths = try JSONDecoder().decode([String].self, from: XCTUnwrap(setting.pendingSyncDeletions))
        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(urls.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        try LibraryService.deleteAll(saved, sync: LibrarySyncService())

        try assertEmpty(container)
        XCTAssertNil(setting.pendingSyncDeletions)
        XCTAssertTrue(urls.allSatisfy { !FileManager.default.fileExists(atPath: $0.path) })
    }

    func testSettingsDeletionClearsCacheResultsAndPreviousError() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Article.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PDFFile(url))
        try context.save()
        let content = LibraryContentService(sync: sync, { _ in "searchable text" })
        try await XCTUnwrap(content.refreshContentCache(context)).value
        XCTAssertNotNil(content.state.cacheRefreshResult)
        let state = SettingsViewState()
        state.appError = .error("Previous failure")

        XCTAssertTrue(SettingsViewService.deleteLibrary(state, context, sync: sync, contentService: content))

        try assertEmpty(container)
        XCTAssertNil(state.appError)
        XCTAssertNil(content.state.cacheRefreshResult)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testSettingsDeletionReportsUnresolvableBookmarkWithoutRemovingEntry() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Keep.pdf")
        try Data("keep".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        context.insert(PDFFile(url, Data([0, 1])))
        try context.save()
        let state = SettingsViewState()

        XCTAssertFalse(SettingsViewService.deleteLibrary(state, context, sync: sync, contentService: LibraryContentService(sync: sync)))

        XCTAssertNotNil(state.appError)
        XCTAssertEqual(state.errorTitle, "Library Could Not Be Deleted")
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try Data(contentsOf: url), Data("keep".utf8))
    }

    func testDeletionRequestWaitsForConfirmationAndPreservesDisplayedPDF() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Keep.pdf")
        try Data("keep".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        let pdf = PDFFile(url)
        context.insert(pdf)
        try context.save()
        let state = LibraryViewState()
        state.selectedPDFFile = pdf
        state.currentPageIndex = 3

        LibraryViewService.requestDeletion(state, context, pdf, sync: sync)

        XCTAssertTrue(state.showDeleteConfirmation)
        XCTAssertEqual(state.pendingDeletionPDFFile?.persistentModelID, pdf.persistentModelID)
        XCTAssertEqual(state.selectedPDFFile?.persistentModelID, pdf.persistentModelID)
        XCTAssertEqual(state.currentPageIndex, 3)
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try Data(contentsOf: url), Data("keep".utf8))
    }

    func testConfirmingDeletionRemovesOnlyTheRequestedPDF() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let urls = ["Delete.pdf", "Keep.pdf"].map { directory.appendingPathComponent($0) }
        let container = try makeContainer()
        let context = container.mainContext
        for url in urls {
            try Data("fixture".utf8).write(to: url)
            context.insert(PDFFile(url))
        }
        try context.save()
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first { $0.url == urls[0] })
        let state = LibraryViewState()
        LibraryViewService.requestDeletion(state, context, pdf, sync: sync)

        LibraryViewService.confirmDeletion(state, context, sync: sync)

        XCTAssertFalse(state.showDeleteConfirmation)
        XCTAssertNil(state.pendingDeletionPDFFile)
        XCTAssertNil(state.appError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: urls[0].path))
        XCTAssertEqual(try Data(contentsOf: urls[1]), Data("fixture".utf8))
        XCTAssertEqual(try ModelContext(container).fetchCount(FetchDescriptor<PDFFile>()), 1)
    }

    func testDisablingConfirmationDeletesWithoutPresentingDialog() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Delete.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        let pdf = PDFFile(url)
        context.insert(pdf)
        try context.save()
        try StorageSettingsService.saveDeletion(context, false, false)
        let state = LibraryViewState()

        LibraryViewService.requestDeletion(state, context, pdf, sync: sync)

        XCTAssertFalse(state.showDeleteConfirmation)
        XCTAssertNil(state.pendingDeletionPDFFile)
        XCTAssertNil(state.appError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        try assertEmpty(container)
    }

    func testTrashRetryClearsPendingDeletionForAnAlreadyMissingFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let container = try makeContainer()
        let context = container.mainContext
        let storage = StorageSettings(.fixed)
        storage.moveDeletedFilesToTrash = true
        storage.pendingSyncDeletions = try JSONEncoder().encode(["Missing.pdf"])
        context.insert(storage)
        try context.save()

        try LibraryService.retrySyncedFileDeletions(context, storage, directory)

        XCTAssertNil(storage.pendingSyncDeletions)
        XCTAssertNil(try ModelContext(container).fetch(FetchDescriptor<StorageSettings>()).first?.pendingSyncDeletions)
    }

    private func assertEmpty(_ container: ModelContainer, file: StaticString = #filePath, line: UInt = #line) throws {
        let context = ModelContext(container)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0, file: file, line: line)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0, file: file, line: line)
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
        return container
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
