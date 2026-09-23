import Combine
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class SettingsViewServiceTests: XCTestCase {
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
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .flexibility))

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
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed))

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

        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed))
        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .flexibility))

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

        XCTAssertTrue(SettingsViewService.saveStorage(state, context, .fixed))

        XCTAssertNil(state.appError)
        XCTAssertEqual(publicationCount, 1)
        let readContext = ModelContext(container)
        let settings = try readContext.fetch(FetchDescriptor<StorageSettings>())
        XCTAssertEqual(settings.first?.storage, .fixed)
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
