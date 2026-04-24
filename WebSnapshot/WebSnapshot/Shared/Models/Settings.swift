import SwiftData

enum Appearance: String, CaseIterable, Codable, Hashable, Identifiable {
    case light
    case dark
    case system

    var id: String {
        rawValue
    }
}

@Model
final class GeneralSettings {
    var appearance: Appearance
    
    init(_ appearance: Appearance) {
        self.appearance = appearance
    }
}
