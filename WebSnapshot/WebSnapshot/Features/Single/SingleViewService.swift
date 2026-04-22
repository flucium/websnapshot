import Foundation
import SwiftData


enum SingleViewService{
    @MainActor
    static func save(_ url:URL?,_ modelContext: ModelContext) throws{
        guard let url else {
            return
        }

        try DirectoryService.save(url, modelContext)
    }
}
