import Foundation
import SwiftData
import WebKit

@MainActor
enum WebCaptureService {
    static func capture( _ url: URL, _ modelContext: ModelContext, _ onStart: (WebPage) -> Void ) async throws -> URL? {
        
        guard url.isSupportedWebURL else {
            throw AppError.invalidURL("Enter a valid HTTP or HTTPS address.")
        }
        
        let page = try await WebService.fetch(url, onStart)
        
        let document = try await WebService.export(page)
        
        try Task.checkCancellation()
        
        let settings = try modelContext.fetch(FetchDescriptor<StorageSettings>())
        
        return try save(document, page.title, page.url, modelContext,  settings)
    }

    @discardableResult
    static func save( _ document: PDFFileDocument, _ title: String, _ url: URL?, _ modelContext: ModelContext, _ storageSettings: [StorageSettings], _ chooseDestination: @MainActor (String, URL?, PDFFileDocument?) throws -> URL? = savePanel ) throws -> URL? {
        
        switch StorageSettingsService.storage(storageSettings) {
        case .flexibility:
        
            guard let destination = try chooseDestination(title, url, document) else {
                return nil
            }
            
            try PDFFileService.save(modelContext, destination)
            
            return destination

        case .fixed:
            
            guard let directory = try StorageSettingsService.fixedStorageURL(storageSettings) else {
                throw AppError.error("Choose a storage folder in Settings before saving.")
            }
            
            let isAccessing = directory.startAccessingSecurityScopedResource()
            
            defer {
                if isAccessing { directory.stopAccessingSecurityScopedResource() }
            }
            
            guard let destination = try saveToDirectory(title, url, document, directory) else {
                return nil
            }
            
            try PDFFileService.save(modelContext, destination)
            
            return destination
        }
    }
}
