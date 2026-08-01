import Foundation
import SwiftData


final class AppearanceSettingsService {
    
    static func appearance(
        _ settings: [AppearanceSettings]
    ) -> AppearanceSettings.Appearance {
        settings.first?.appearance ?? .system
    }
    
    static func title(
        _ appearance: AppearanceSettings.Appearance
    ) -> String {
        switch appearance {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }
    
    static func save(
        _ modelContext:ModelContext,
        _ appearance: AppearanceSettings.Appearance
    ) throws  {
        do {
            try upsert(
                modelContext,
                appearance
            )
        } catch let error as AppError {
            modelContext
                .rollback()
            throw error
        } catch {
            modelContext
                .rollback()
            throw AppError
                .system(
                    "The appearance setting could not be saved.",
                    error.localizedDescription,
                    error
                )
        }
    }
    
    static func load(
        _ modelContext: ModelContext
    )throws -> AppearanceSettings {
        
        do{
            let settings = try fetch(
                modelContext
            )
            
            return settings.first ?? AppearanceSettings(
                .system
            )
            
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError
                .system(
                    "The appearance setting could not be loaded.",
                    error.localizedDescription,
                    error
                )
        }
        
    }
    
    static func reset(
        _ modelContext: ModelContext
    ) throws{
        do {
            try upsert(
                modelContext,
                .system
            )
        } catch let error as AppError {
            modelContext
                .rollback()
            throw error
        } catch {
            modelContext
                .rollback()
            throw AppError
                .system(
                    "The appearance setting could not be reset.",
                    error.localizedDescription,
                    error
                )
        }
    }
    
    private static func upsert(
        _ modelContext:ModelContext,
        _ appearance: AppearanceSettings.Appearance
    ) throws{
        let settings = try fetch(
            modelContext
        )
        
        let current = settings.first ?? AppearanceSettings(
            appearance
        )
        
        if settings.isEmpty {
            modelContext
                .insert(
                    current
                )
        } else {
            current.appearance = appearance
        }
        
        for duplicated in settings
            .dropFirst() {
            modelContext
                .delete(
                    duplicated
                )
        }
        
        try modelContext
            .save()
    }
    
    
    private static func fetch(
        _ modelContext:ModelContext
    ) throws -> [AppearanceSettings] {
        return try modelContext
            .fetch(
                FetchDescriptor<AppearanceSettings>()
            )
    }
    
}
