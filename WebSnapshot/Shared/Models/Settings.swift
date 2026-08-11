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
    var fixedStoragePath: String
    
    init(_ storage: Storage) {
        self.storage = storage
        
        self.fixedStoragePath = "$HOME/Documents/WebSnapshot/"
    }
    
    init(_ storage: Storage,_ fixedStoragePath: String) {
        
        self.storage = storage
        
        if storage == .fixed && !fixedStoragePath.isEmpty{
            self.fixedStoragePath = fixedStoragePath
        }else{
            self.fixedStoragePath = "$HOME/Documents/WebSnapshot/"
        }
    }
}

extension StorageSettings{
    enum Storage: String, CaseIterable, Codable, Hashable, Identifiable {
        case fixed
        case flexible
        case local
        case removable
        
        var id: String {
            rawValue
        }
    }
}
