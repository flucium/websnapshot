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

@Model
final class StorageSettings {
    var storage: Storage
    
    var fixedStoragePath: String?
    
    var fixedStorageBookmarkData: Data?

    var syncEnabled: Bool = false

    var syncDriveBookmarkData: Data? = nil

    var syncDrivePath: String? = nil
    
    var syncFolderBookmarkData: Data? = nil
    
    var syncFolderPath: String? = nil
    
    var previousStorageRawValue: String? = nil
    
    var previousFixedStoragePath: String? = nil
    
    var previousFixedStorageBookmarkData: Data? = nil
    
    var syncDeviceID: UUID? = nil
    
    var syncCounter: Int64 = 0
    
    var pendingSyncChanges: Data? = nil

    init(_ storage: Storage) {
        self.storage = storage
        self.fixedStoragePath = nil
        self.fixedStorageBookmarkData = nil
    }
}

extension StorageSettings {
    enum Storage: String, CaseIterable, Codable, Hashable, Identifiable {
        case fixed
        case flexibility

        var id: String {
            rawValue
        }
    }
}
