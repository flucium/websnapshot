import Foundation
import SwiftData

@MainActor
enum PDFFileService {
    static func register(_ context: ModelContext, _ url: URL, _ sourceURL: URL? = nil) throws {
       
        let bookmark = try URL.securityScopedBookmarkData(url)
        
        let entries = try context.fetch(FetchDescriptor<PDFFile>())
        
        _ = try updateLocations(entries)
        

        if let pdfFile = entries.first(where: {
            normalizedURL($0.url) == normalizedURL(url)
        }) {
        
            pdfFile.bookmarkData = bookmark
            
            pdfFile.searchableText = nil
            
            pdfFile.contentFingerprint = nil

            if let sourceURL {
                pdfFile.sourceURL = sourceURL
                pdfFile.addedAt = Date()
            }
            
        } else {
            context.insert(PDFFile(url, bookmark, Date(), sourceURL))
        }
    }

    static func registerUntracked(_ urls: [URL], _ context: ModelContext) throws {
        guard !urls.isEmpty else {
            return
        }

        let entries = try context.fetch(FetchDescriptor<PDFFile>())
        
        var registered = Set(entries.filter { !$0.isDeleted }.map {
            normalizedURL((try? $0.resolveURL()) ?? $0.url)
        })

        for url in urls where registered.insert(normalizedURL(url)).inserted {
            let bookmark = try URL.securityScopedBookmarkData(url)
            context.insert(PDFFile(url, bookmark, Date()))
        }
    }

    static func entries(_ context: ModelContext, matching url: URL) throws -> [PDFFile] {
        let fileURL = normalizedURL(url)
        
        return try context.fetch(FetchDescriptor<PDFFile>()).filter {
            normalizedURL($0.url) == fileURL
        }
    }

    static func remove(_ pdfFiles: [PDFFile], _ context: ModelContext) {
        PDFTagService.deleteTagsOrphanedByDeleting(pdfFiles, context)
        
        for pdfFile in pdfFiles {
            context.delete(pdfFile)
        }
    }

    static func refreshLocations(_ context: ModelContext) throws -> Bool {
        try updateLocations(context.fetch(FetchDescriptor<PDFFile>()))
    }

    static func deleteMissingFiles(_ context: ModelContext, _ pdfFiles: [PDFFile], _ confirmedDeletedIDs: Set<PersistentIdentifier> = [] ) -> Bool {
        
        let missing = pdfFiles.filter {
            $0.availability == .missing || (confirmedDeletedIDs.contains($0.persistentModelID) && !FileIO.exists($0.resolvedURL))
        }
        
        remove(missing, context)
        
        return !missing.isEmpty
    }

    private static func updateLocations(_ pdfFiles: [PDFFile]) throws -> Bool {
        var changed = false
        
        for pdfFile in pdfFiles {
            guard let resolvedURL = try? pdfFile.resolveURL() else {
                continue
            }
        
            let currentURL = resolvedURL.standardizedFileURL
            
            guard pdfFile.url != currentURL else {
                continue
            }
            
            let bookmark = try URL.securityScopedBookmarkData(resolvedURL)
            
            pdfFile.url = currentURL
            
            pdfFile.bookmarkData = bookmark
            
            changed = true
        }
        
        return changed
    }

    private static func normalizedURL(_ url: URL) -> URL {
        let resolvedURL = url.resolvingSymlinksInPath()
        
        return resolvedURL.deletingLastPathComponent().resolvingSymlinksInPath() .appendingPathComponent(resolvedURL.lastPathComponent).standardizedFileURL
    }
}
