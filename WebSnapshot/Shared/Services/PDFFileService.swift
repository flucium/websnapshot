import Foundation
import SwiftData

final class PDFFileService {
    static func save(_ modelContext: ModelContext,_ url:URL) throws {
        
        let bookmarkData: Data
        
        do {
            bookmarkData = try URL.securityScopedBookmarkData(url)
        } catch {
            throw AppError(error)
        }
        
        do{
            let entries = try fetch(modelContext)
            
            try updateLocations(entries)
            
            if let pdfFile = entries.first(where: {
                $0.url.standardizedFileURL == url.standardizedFileURL
            }) {
                
                pdfFile.bookmarkData = bookmarkData
                
                try modelContext.save()
                
            }else{
                modelContext.insert(PDFFile(url,bookmarkData))
                
                try modelContext.save()
            }
            
        } catch let error as AppError {
            modelContext.rollback()
            
            throw error
        } catch {
            modelContext.rollback()
            
            throw AppError.system("The PDF could not be added to the library.",error.localizedDescription,error)
        }
    }

    static func refreshLocations(_ modelContext: ModelContext) throws {
        
        do {
        
            if try updateLocations(fetch(modelContext)) {
                try modelContext.save()
            }
            
        } catch {
            
            modelContext.rollback()
            
            throw AppError.system("The library's file locations could not be updated before saving.",error.localizedDescription,error)
        }
    }

    @discardableResult
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
    
    static func delete(_ modelContext: ModelContext ,_ url: URL) throws {
        do{
            let matched = try fetch(modelContext).filter {
                $0.url == url
            }
            
            PDFTagService.deleteTagsOrphanedByDeleting(matched, in: modelContext)

            for entry in matched {
                modelContext.delete(entry)
            }
            
            if matched.isEmpty == false{
                try modelContext.save()
            }
            
        } catch let error as AppError {
            modelContext.rollback()
            
            throw error
        } catch {
            modelContext.rollback()
            
            throw AppError.system("The PDF could not be removed from the library.",error.localizedDescription,error)
        }
    }
    
    
    static func refreshBookmarks(_ pdfFileURLs: [URL],_ modelContext: ModelContext) throws {
        
        let pdfFilePaths = Set(pdfFileURLs.map{
            $0.standardizedFileURL.path
        })
        
        guard pdfFilePaths.isEmpty == false else {
            return
        }
        
        var needs = false
        
        do {
            for pdfFile in try fetch(modelContext) {
                let fileURL = pdfFile.resolvedURL
                
                guard pdfFilePaths.contains(fileURL.deletingLastPathComponent().standardizedFileURL.path) else {
                    continue
                }
                
                let bookmarkData: Data
                
                do {
                    bookmarkData = try URL.securityScopedBookmarkData(fileURL)
                } catch {
                    AppLogger.record(AppError(error), "Refresh PDF bookmark",fileURL)
                    
                    continue
                }
                
                pdfFile.bookmarkData = bookmarkData
                
                needs = true
            }
            
            if needs {
                try modelContext.save()
            }
            
        } catch let error as AppError {
            modelContext.rollback()
            
            throw error
        } catch {
            modelContext.rollback()
            
            throw AppError.system("File access permissions could not be refreshed.",error.localizedDescription,error)
        }
    }
    
    private static func fetch(_ modelContext:ModelContext) throws -> [PDFFile] {
        return try modelContext.fetch(FetchDescriptor<PDFFile>())
    }
}
