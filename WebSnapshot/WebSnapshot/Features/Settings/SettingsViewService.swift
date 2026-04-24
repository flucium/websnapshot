import SwiftData

enum SettingsViewService {

    static func appearance(_ settings: [GeneralSettings]) -> Appearance {
        settings.first?.appearance ?? .system
    }

    static func title(_ appearance: Appearance) -> String {
        switch appearance {
        case .light:
            return "Light"
        case .dark:
            return "Dark"
        case .system:
            return "System"
        }
    }

    @MainActor
    static func save(_ appearance: Appearance, _ modelContext: ModelContext) throws {
        try GeneralSettingsService.save(appearance, modelContext)
    }
}
