import Combine
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class SettingsViewServiceTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testUnchangedDefaultsDoNotCreateSettingsOrPublish() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let state = SettingsViewState()
        var publicationCount = 0
        let subscription = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { subscription.cancel() }

        XCTAssertTrue(SettingsViewService.saveAppearance(state, context, .system))
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .flexibility, sync: sync))
        XCTAssertTrue(SettingsViewService.saveDeletion(state, context, true, true))

        XCTAssertTrue(try context.fetch(FetchDescriptor<AppearanceSettings>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<StorageSettings>()).isEmpty)
        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(state.appError)
        XCTAssertEqual(publicationCount, 0)
    }

    func testUnchangedExistingValuesPreserveErrorAndDoNotSavePendingChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let appearance = AppearanceSettings(.dark)
        let storage = StorageSettings(.fixed)
        context.insert(appearance)
        context.insert(storage)
        try context.save()

        storage.fixedStoragePath = "/tmp/pending-storage-folder"
        XCTAssertTrue(context.hasChanges)

        let state = SettingsViewState()
        let previousError = AppError.error("Previous failure")
        state.appError = previousError
        var publicationCount = 0
        let subscription = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { subscription.cancel() }

        XCTAssertTrue(SettingsViewService.saveAppearance(state, context, .dark))
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed, sync: sync))
        XCTAssertTrue(SettingsViewService.saveDeletion(state, context, true, true))

        XCTAssertTrue(context.hasChanges)
        XCTAssertEqual(state.appError, previousError)
        XCTAssertEqual(publicationCount, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<AppearanceSettings>()).count, 1)
        XCTAssertEqual(try context.fetch(FetchDescriptor<StorageSettings>()).count, 1)

        let readContext = ModelContext(container)
        let savedStorage = try XCTUnwrap(
            readContext.fetch(FetchDescriptor<StorageSettings>()).first
        )
        XCTAssertNil(savedStorage.fixedStoragePath)
    }

    func testAppearanceChangesPersistOneRecordWithoutPublishingAnEmptyError() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let state = SettingsViewState()
        var publicationCount = 0
        let subscription = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { subscription.cancel() }

        XCTAssertTrue(SettingsViewService.saveAppearance(state, context, .dark))
        XCTAssertTrue(SettingsViewService.saveAppearance(state, context, .light))

        let readContext = ModelContext(container)
        let settings = try readContext.fetch(FetchDescriptor<AppearanceSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.appearance, .light)
        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(state.appError)
        XCTAssertEqual(publicationCount, 0)
    }

    func testStorageChangesPersistOneRecordWithoutPublishingAnEmptyError() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let state = SettingsViewState()
        var publicationCount = 0
        let subscription = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { subscription.cancel() }

        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed, sync: sync))
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .flexibility, sync: sync))

        let readContext = ModelContext(container)
        let settings = try readContext.fetch(FetchDescriptor<StorageSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.storage, .flexibility)
        XCTAssertFalse(context.hasChanges)
        XCTAssertNil(state.appError)
        XCTAssertEqual(publicationCount, 0)
    }

    func testSuccessfulAppearanceChangeClearsExistingErrorOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let state = SettingsViewState()
        state.appError = .error("Previous appearance failure")
        var publicationCount = 0
        let subscription = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { subscription.cancel() }

        XCTAssertTrue(SettingsViewService.saveAppearance(state, context, .dark))

        XCTAssertNil(state.appError)
        XCTAssertEqual(publicationCount, 1)
        let readContext = ModelContext(container)
        let settings = try readContext.fetch(FetchDescriptor<AppearanceSettings>())
        XCTAssertEqual(settings.first?.appearance, .dark)
    }

    func testSuccessfulStorageChangeClearsExistingErrorOnce() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let state = SettingsViewState()
        state.appError = .error("Previous storage failure")
        var publicationCount = 0
        let subscription = state.objectWillChange.sink {
            publicationCount += 1
        }
        defer { subscription.cancel() }

        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed, sync: sync))

        XCTAssertNil(state.appError)
        XCTAssertEqual(publicationCount, 1)
        let readContext = ModelContext(container)
        let settings = try readContext.fetch(FetchDescriptor<StorageSettings>())
        XCTAssertEqual(settings.first?.storage, .fixed)
    }

    func testDeletionChangesPersistWithoutChangingStorageOrSyncSettings() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let storage = StorageSettings(.fixed)
        storage.fixedStoragePath = "/tmp/storage"
        storage.fixedStorageBookmarkData = Data([1, 2])
        storage.syncEnabled = true
        storage.syncDrivePath = "/tmp/drive"
        storage.syncDriveBookmarkData = Data([3, 4])
        storage.syncFolderPath = "/tmp/drive/websnapshot"
        storage.syncFolderBookmarkData = Data([5, 6])
        storage.pendingSyncDeletions = Data("[]".utf8)
        context.insert(storage)
        try context.save()
        let state = SettingsViewState()
        state.appError = .error("Previous failure")

        for confirmBeforeDeleting in [false, true] {
            for moveDeletedFilesToTrash in [true, false] {
                XCTAssertTrue(SettingsViewService.saveDeletion(state, context, confirmBeforeDeleting, moveDeletedFilesToTrash))

                let settings = try ModelContext(container).fetch(FetchDescriptor<StorageSettings>())
                let saved = try XCTUnwrap(settings.first)
                XCTAssertEqual(settings.count, 1)
                XCTAssertEqual(saved.confirmBeforeDeleting, confirmBeforeDeleting)
                XCTAssertEqual(saved.moveDeletedFilesToTrash, moveDeletedFilesToTrash)
                XCTAssertEqual(saved.storage, .fixed)
                XCTAssertEqual(saved.fixedStoragePath, "/tmp/storage")
                XCTAssertEqual(saved.fixedStorageBookmarkData, Data([1, 2]))
                XCTAssertTrue(saved.syncEnabled)
                XCTAssertEqual(saved.syncDrivePath, "/tmp/drive")
                XCTAssertEqual(saved.syncDriveBookmarkData, Data([3, 4]))
                XCTAssertEqual(saved.syncFolderPath, "/tmp/drive/websnapshot")
                XCTAssertEqual(saved.syncFolderBookmarkData, Data([5, 6]))
                XCTAssertEqual(saved.pendingSyncDeletions, Data("[]".utf8))
                XCTAssertFalse(context.hasChanges)
                XCTAssertNil(state.appError)
            }
        }
    }

    func testDeletionChangesCreateOneRecordAndSurviveStorageChanges() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let state = SettingsViewState()

        XCTAssertTrue(SettingsViewService.saveDeletion(state, context, false, true))
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed, sync: sync))
        try StorageSettingsService.reset(context, sync: sync)

        let settings = try ModelContext(container).fetch(FetchDescriptor<StorageSettings>())
        XCTAssertEqual(settings.count, 1)
        XCTAssertFalse(try XCTUnwrap(settings.first).confirmBeforeDeleting)
        XCTAssertTrue(try XCTUnwrap(settings.first).moveDeletedFilesToTrash)
        XCTAssertEqual(settings.first?.storage, .flexibility)
    }

    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AppearanceSettings.self,
            StorageSettings.self,
            configurations: configuration
        )
        container.mainContext.autosaveEnabled = false
        return container
    }
}
