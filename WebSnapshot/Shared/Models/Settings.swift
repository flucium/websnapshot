import Foundation
import SwiftData

@Model
final class AppearanceSettings{
    var appearance: Appearance
    
    init(_ appearance: Appearance) {
        self.appearance = appearance
    }
}

extension AppearanceSettings{
    enum Appearance: String, CaseIterable, Codable, Hashable, Identifiable {
        case light
        case dark
        case system

        var id: String {
            rawValue
        }
    }
}
