import Foundation
import SwiftData

@MainActor
enum PDFFileService {
    static func register(_ context: ModelContext, _ url: URL) throws {
       
        let bookmark = try URL.securityScopedBookmarkData(url)
        
        let entries = try context.fetch(FetchDescriptor<PDFFile>())
        
        _ = try updateLocations(entries)
        

        if let pdf = entries.first(where: {
            normalizedURL($0.url) == normalizedURL(url)
        }) {
        
            pdf.bookmarkData = bookmark
            
            pdf.searchableText = nil
            
            pdf.contentFingerprint = nil
            
        } else {
            context.insert(PDFFile(url, bookmark, Date()))
        }
    }

    static func entries(_ context: ModelContext, matching url: URL) throws -> [PDFFile] {
        let fileURL = normalizedURL(url)
        
        return try context.fetch(FetchDescriptor<PDFFile>()).filter {
            normalizedURL($0.url) == fileURL
        }
    }

    static func remove(_ pdfs: [PDFFile], _ context: ModelContext) {
        PDFTagService.deleteTagsOrphanedByDeleting(pdfs, context)
        
        for pdf in pdfs {
            context.delete(pdf)
        }
    }

    static func refreshLocations(_ context: ModelContext) throws -> Bool {
        try updateLocations(context.fetch(FetchDescriptor<PDFFile>()))
    }

    static func deleteMissingFiles(_ context: ModelContext, _ pdfs: [PDFFile], _ confirmedDeletedIDs: Set<PersistentIdentifier> = [] ) -> Bool {
        
        let missing = pdfs.filter {
            $0.availability == .missing || (confirmedDeletedIDs.contains($0.persistentModelID) && !FileIO.exists($0.resolvedURL))
        }
        
        remove(missing, context)
        
        return !missing.isEmpty
    }

    private static func updateLocations(_ entries: [PDFFile]) throws -> Bool {
        var changed = false
        
        for entry in entries {
            guard let resolvedURL = try? entry.resolveURL() else {
                continue
            }
        
            let currentURL = resolvedURL.standardizedFileURL
            
            guard entry.url != currentURL else {
                continue
            }
            
            let bookmark = try URL.securityScopedBookmarkData(resolvedURL)
            
            entry.url = currentURL
            
            entry.bookmarkData = bookmark
            
            changed = true
        }
        
        return changed
    }

    private static func normalizedURL(_ url: URL) -> URL {
        let resolvedURL = url.resolvingSymlinksInPath()
        
        return resolvedURL.deletingLastPathComponent().resolvingSymlinksInPath() .appendingPathComponent(resolvedURL.lastPathComponent).standardizedFileURL
    }
}
