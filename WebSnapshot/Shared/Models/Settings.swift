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

@Model class StorageSettings{
    var storage: Storage
    
    init(_ storage: Storage) {
        self.storage = storage
    }
}

extension StorageSettings{
    enum Storage: String, CaseIterable, Codable, Hashable, Identifiable {
        case fixed
        case custom
        case local
        case removable
        
        var id: String {
            rawValue
        }
    }
}
