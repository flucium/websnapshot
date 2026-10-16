import Foundation
import SwiftData


final class AppearanceSettingsService {
    
    static func appearance(_ settings: [AppearanceSettings]) -> AppearanceSettings.Appearance {
        settings.first?.appearance ?? .system
    }
    
    static func title(_ appearance: AppearanceSettings.Appearance) -> String {
        switch appearance {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }
    
    static func save(_ modelContext:ModelContext, _ appearance: AppearanceSettings.Appearance) throws  {
        do {
            try upsert( modelContext, appearance)
        } catch let error as AppError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw AppError.system("The appearance setting could not be saved.",error.localizedDescription,error)
        }
    }
    
    static func load(_ modelContext: ModelContext)throws -> AppearanceSettings {
        do{
            let settings = try fetch(modelContext)
            
            return settings.first ?? AppearanceSettings(.system)
            
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.system("The appearance setting could not be loaded.",error.localizedDescription,error)
        }
        
    }
    
    static func reset(_ modelContext: ModelContext) throws{
        do {
            try upsert(modelContext,.system)
        } catch let error as AppError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            
            throw AppError.system("The appearance setting could not be reset.",error.localizedDescription,error)
        }
    }
    
    private static func upsert(_ modelContext:ModelContext,_ appearance: AppearanceSettings.Appearance) throws{
        let settings = try fetch(modelContext)
        
        let current = settings.first ?? AppearanceSettings(appearance)
        
        if settings.isEmpty {
            modelContext.insert(current)
        } else {
            current.appearance = appearance
        }
        
        for duplicated in settings.dropFirst() {
            modelContext.delete(duplicated)
        }
        
        try modelContext.save()
    }
    
    
    private static func fetch(_ modelContext:ModelContext) throws -> [AppearanceSettings] {
        return try modelContext.fetch(FetchDescriptor<AppearanceSettings>())
    }
    
}

final class StorageSettingsService {

    static func storage(_ settings: [StorageSettings]) -> StorageSettings.Storage {
        
        if settings.first?.syncEnabled == true {
            
            return .fixed
        
        }
        
        return settings.first?.storage ?? .flexibility
    }

    static func fixedStoragePath(_ settings: [StorageSettings]) -> String? {
        
        if settings.first?.syncEnabled == true {
            
            return settings.first?.syncFolderPath
        
        }
        
        return settings.first?.fixedStoragePath
    }

    static func fixedStorageURL(_ settings: [StorageSettings]) throws -> URL? {
        
        if let setting = settings.first, setting.syncEnabled {
        
            return try LibrarySyncService.shared.folderURL(setting)
        
        }
        
        guard let bookmarkData = settings.first?.fixedStorageBookmarkData else {
            return nil
        }

        var isStale = false
        
        let url: URL

        do {
            url = try URL.resolveSecurityScopedBookmarkData(bookmarkData, &isStale)
        } catch {
            guard FileIO.isMissingFileError(error), let path = settings.first?.fixedStoragePath else {
                throw error
            }

            return URL(fileURLWithPath: path, isDirectory: true)
        }

        if FileIO.isInTrash(url) {
            return settings.first?.fixedStoragePath.map {
                URL(fileURLWithPath: $0, isDirectory: true)
            }
        }

        if isStale {
            AppLogger.recordDiagnostic("The fixed storage bookmark is stale.","Resolve fixed storage folder",url)
        }

        return url
    }

    static func title(_ storage: StorageSettings.Storage) -> String {
        switch storage {
        case .fixed:
            return "Fixed"
        case .flexibility:
            return "Flexibility"
        }
    }

    static func save(_ modelContext: ModelContext,_ storage: StorageSettings.Storage) throws {
        try LibrarySyncService.shared.requireReady()
        
        if LibrarySyncService.isEnabled(modelContext), storage != .fixed {
        
            throw AppError.error("Storage is fixed to iCloud Drive/websnapshot while Sync is on.")
        
        }
        
        do {
            try upsert(modelContext,storage)
        } catch let error as AppError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw AppError.system("The storage setting could not be saved.",error.localizedDescription,error)
        }
    }

    static func saveFixedStorage(_ modelContext: ModelContext,_ url: URL) throws {
        try LibrarySyncService.shared.requireReady()
        
        if LibrarySyncService.isEnabled(modelContext) {
            throw AppError.error("The storage folder cannot be changed while Sync is on.")
        }
        
        do {
            
            let bookmarkData = try URL.securityScopedBookmarkData(url)

            try upsert(modelContext, .fixed) {
                settings in
                
                settings.storage = .fixed
                
                settings.fixedStoragePath = url.path
            
                settings.fixedStorageBookmarkData = bookmarkData
            }
            
        } catch let error as AppError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            throw AppError.system("The fixed storage folder could not be saved.",error.localizedDescription,error)
        }
    }

    static func load(_ modelContext: ModelContext) throws -> StorageSettings {
        do {
            let settings = try fetch(modelContext)

            return settings.first ?? StorageSettings(.flexibility)
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.system("The storage setting could not be loaded.",error.localizedDescription,error)
        }
    }

    static func reset(_ modelContext: ModelContext) throws {
        try LibrarySyncService.shared.requireReady()
        
        if LibrarySyncService.isEnabled(modelContext) {
            throw AppError.error("Turn off Sync before resetting Storage.")
        }
        
        do {
            
            try upsert(modelContext,.flexibility) {
                settings in
                
                settings.storage = .flexibility
                
                settings.fixedStoragePath = nil
                
                settings.fixedStorageBookmarkData = nil
            }
            
        } catch let error as AppError {
            modelContext.rollback()
            throw error
        } catch {
            modelContext.rollback()
            
            throw AppError.system("The storage setting could not be reset.",error.localizedDescription,error)
        }
    }

    private static func upsert(_ modelContext: ModelContext,_ storage: StorageSettings.Storage,_ update: ((StorageSettings) -> Void)? = nil) throws {
        
        let settings = try fetch(modelContext)
        
        let current = settings.first ?? StorageSettings(storage)
        
        if settings.isEmpty {
            modelContext.insert(current)
        } else {
            current.storage = storage
        }

        update?(current)

        for duplicated in settings.dropFirst() {
            modelContext.delete(duplicated)
        }

        try modelContext.save()
    }

    private static func fetch(_ modelContext: ModelContext) throws -> [StorageSettings] {
        try modelContext.fetch(FetchDescriptor<StorageSettings>())
    }
}
