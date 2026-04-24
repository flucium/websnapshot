import Foundation
import SwiftData

final class GeneralSettingsService {

    @discardableResult
    static func save(_ appearance: Appearance, _ modelContext: ModelContext) throws -> GeneralSettings {
        do {
            return try upsert(appearance, modelContext)
        } catch {
            throw AppError(error)
        }
    }

    @discardableResult
    static func reset(_ modelContext: ModelContext) throws -> GeneralSettings {
        do {
            return try upsert(.system, modelContext)
        } catch {
            throw AppError(error)
        }
    }

    private static func upsert(_ appearance: Appearance, _ modelContext: ModelContext) throws -> GeneralSettings {
        let settings = try modelContext.fetch(FetchDescriptor<GeneralSettings>())
        
        let current = settings.first ?? GeneralSettings(appearance)

        if settings.isEmpty {
            modelContext.insert(current)
        } else {
            current.appearance = appearance
        }

        for duplicated in settings.dropFirst() {
            modelContext.delete(duplicated)
        }

        try modelContext.save()
        
        return current
    }
}
