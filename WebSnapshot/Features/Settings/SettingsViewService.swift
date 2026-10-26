import Foundation
import SwiftData

@MainActor
final class SettingsViewService {
    static func changeSync(_ state: SettingsViewState, _ context: ModelContext, _ enabled: Bool, sync: LibrarySyncService, chooseDirectory: @MainActor (URL?, String, String) -> URL? = directoryPanel) async -> Bool {
        
        do {
            try sync.requireReady()
            
            guard LibrarySyncService.isEnabled(context) != enabled else {
                return true
            }
            
            if enabled {
                let saved = try LibrarySyncService.settings(context)
        
                if saved?.syncDriveBookmarkData != nil {
                
                    try await sync.setEnabled(true, context)
                    
                } else {
                    
                    guard let selected = chooseDirectory(SyncFileStore.defaultCloudDriveURL, "Allow Access to iCloud Drive", "Enable Sync") else {
                        return false
                    }
                    try await sync.setEnabled(true, context, drive: selected)
                }
                
            } else {
                guard let saved = try LibrarySyncService.settings(context) else {
                    return false
                }
                
                if try LibrarySyncService.localStorageURL(saved) != nil {
                    try await sync.setEnabled(false, context)
                } else {
                    
                    let initial = saved.previousFixedStoragePath.map {
                        URL(fileURLWithPath: $0, isDirectory: true)
                    }
                    
                    guard let selected = chooseDirectory(initial, "Choose Folder for Synced PDFs", "Copy and Turn Off Sync") else {
                        return false
                    }
                    
                    try await sync.setEnabled(false, context, localRoot: selected)
                }
            }
            
            
            clearError(state)
            
            return true
        } catch {
            
            handle(error, "Sync Could Not Be Changed", "Change library sync", state)
            
            return false
        }
        
    }

    static func reconnectSync(_ state: SettingsViewState, _ context: ModelContext, sync: LibrarySyncService) {
        
        guard let selected = directoryPanel(SyncFileStore.defaultCloudDriveURL, "Reconnect iCloud Drive", "Reconnect") else {
            return
        }
        
        do {
            try sync.reconnect(selected, context)
            
            clearError(state)
        } catch {
            handle(error, "Sync Folder Could Not Be Reconnected", "Reconnect sync folder", state)
        }
    }
    
    @discardableResult
    static func saveAppearance(_ state: SettingsViewState,_ modelContext: ModelContext,_ appearance: AppearanceSettings.Appearance) -> Bool {
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
    static func saveStorage(_ state: SettingsViewState,_ modelContext: ModelContext,_ storage: StorageSettings.Storage, sync: LibrarySyncService) -> Bool {
        do {
            guard try StorageSettingsService.load(modelContext).storage != storage else {
                return true
            }

            try StorageSettingsService.save(modelContext, storage, sync: sync)
            
            clearError(state)
            
            return true
        } catch {
            handle(error, "Storage Could Not Be Changed", "Save storage setting", state)
            
            return false
        }
    }

    static func chooseFixedStorage(_ state: SettingsViewState,_ modelContext: ModelContext,_ fixedStoragePath: String?, sync: LibrarySyncService) {
        guard !LibrarySyncService.isEnabled(modelContext), !sync.state.isSwitching else { return }
        
        let currentURL = fixedStoragePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        guard let selectedURL = directoryPanel(currentURL) else {
            return
        }

        do {
            try StorageSettingsService.saveFixedStorage(modelContext, selectedURL, sync: sync)
            
            clearError(state)
        } catch {
            handle(error,"Storage Folder Could Not Be Changed","Save fixed storage folder",state,selectedURL)
        }
    }

    static func refreshContentCache(_ state: SettingsViewState, _ modelContext: ModelContext, _ contentService: LibraryContentService) {
        guard let task = contentService.refreshContentCache(modelContext) else {
            return
        }
        
        clearError(state)

        Task { @MainActor in
            do {
                try await task.value
            } catch {
                handle(error, "Search Cache Could Not Be Refreshed", "Refresh content search cache", state)
            }
        }
    }

    private static func clearError(_ state: SettingsViewState) {
        if state.appError != nil {
            state.appError = nil
        }
    }

    private static func handle(_ error: Error,_ title: String,_ operation: String,_ state: SettingsViewState,_ targetURL: URL? = nil) {
        guard let appError = AppError.presentable(error) else {
            return
        }

        AppLogger.record(appError, operation, targetURL)
        
        state.errorTitle = title
        
        state.appError = appError
    }
}
