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
    
    static func save(_ modelContext:ModelContext,_ appearance: AppearanceSettings.Appearance) throws  {
        do {
            try upsert(modelContext, appearance)
        } catch {
            throw AppError.system("Appearence settings save failed.")
        }
    }

    static func load(_ modelContext: ModelContext)throws -> AppearanceSettings {
        
        do{
            let settings = try fetch(modelContext)
            
            if settings.first == nil{
                return AppearanceSettings(AppearanceSettings.Appearance.system)
            }else{
                return settings.first!
            }
            
        }catch{
            throw AppError.system("Load appearance settings failed.")
        }
        
    }
    
    static func reset(_ modelContext: ModelContext) throws{
        do {
            try upsert(modelContext,.system)
        } catch {
            throw AppError.system("Reset appearance settings failed.")
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
