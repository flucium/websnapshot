import Foundation
import SwiftData

@MainActor
final class SettingsViewService {
    @discardableResult
    static func saveAppearance(
        _ state: SettingsViewState,
        _ modelContext: ModelContext,
        _ appearance: AppearanceSettings.Appearance
    ) -> Bool {
        do {
            guard try AppearanceSettingsService.load(modelContext).appearance != appearance else {
                return true
            }

            try AppearanceSettingsService.save(modelContext, appearance)
            clearError(state)
            return true
        } catch {
            handle(error, "Appearance Could Not Be Changed", "Save appearance setting", state)
            return false
        }
    }

    @discardableResult
    static func saveStorage(
        _ state: SettingsViewState,
        _ modelContext: ModelContext,
        _ storage: StorageSettings.Storage
    ) -> Bool {
        do {
            guard try StorageSettingsService.load(modelContext).storage != storage else {
                return true
            }

            try StorageSettingsService.save(modelContext, storage)
            clearError(state)
            return true
        } catch {
            handle(error, "Storage Could Not Be Changed", "Save storage setting", state)
            return false
        }
    }

    static func chooseFixedStorage(
        _ state: SettingsViewState,
        _ modelContext: ModelContext,
        _ fixedStoragePath: String?
    ) {
        let currentURL = fixedStoragePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        guard let selectedURL = directoryPanel(currentURL) else {
            return
        }

        do {
            try StorageSettingsService.saveFixedStorage(modelContext, selectedURL)
            clearError(state)
        } catch {
            handle(
                error,
                "Storage Folder Could Not Be Changed",
                "Save fixed storage folder",
                state,
                selectedURL
            )
        }
    }

    private static func clearError(_ state: SettingsViewState) {
        if state.appError != nil {
            state.appError = nil
        }
    }

    private static func handle(
        _ error: Error,
        _ title: String,
        _ operation: String,
        _ state: SettingsViewState,
        _ targetURL: URL? = nil
    ) {
        guard let appError = AppError.presentable(error) else { return }

        AppLogger.record(appError, operation, targetURL)
        state.errorTitle = title
        state.appError = appError
    }
}
