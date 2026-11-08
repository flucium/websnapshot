import Foundation
import SwiftData
import WebKit

@MainActor
enum WebCaptureService {
    static func capture(_ url: URL, _ context: ModelContext, sync: LibrarySyncService, chooseDestination: @escaping (String) -> URL?, onProgress: (WebPDFExportState) -> Void = {
        _ in
    }, _ onStart: (WebPage) -> Void ) async throws -> URL? {
        
        guard url.isSupportedWebURL else {
            throw AppError.invalidURL("Enter a valid HTTP or HTTPS address.")
        }
        
        let page = try await WebService.fetch(url, onStart)
        
        let document = try await WebPDFService.export(page, onProgress: onProgress)
        
        try Task.checkCancellation()
        
        let settings = try context.fetch(FetchDescriptor<StorageSettings>())
        
        return try LibraryService.savePDF(document.data, URL.pdfFileName(page.title, page.url), context, settings, sync: sync, chooseDestination: { name in
            let destination = chooseDestination(name)

            return Task.isCancelled ? nil : destination
        })
    }
}
