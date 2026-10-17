import Foundation
import SwiftData

final class PDFFileService {
    
    static func save(_ modelContext: ModelContext, _ url:URL, sync: LibrarySyncService) throws {
        
        try sync.requireReady()
       
        if LibrarySyncService.isEnabled(modelContext) {
            
            do {
                
                try sync.registerPDF(url, modelContext)
                
            }catch {
            
                modelContext.rollback();
                
                throw error
                
            }
            
            return
            
        }
        
        let bookmarkData: Data
        
        do {
            bookmarkData = try URL.securityScopedBookmarkData(url)
        } catch {
            throw AppError(error)
        }
        
        do{
            let entries = try fetch(modelContext)
            
            try updateLocations(entries)
            
            let fileURL = normalizedURL(url)
            
            if let pdfFile = entries.first(where: {
                normalizedURL($0.url) == fileURL
            }) {
                
                pdfFile.bookmarkData = bookmarkData
                
                pdfFile.searchableText = nil
                
                pdfFile.contentFingerprint = nil
                
                try modelContext.save()
                
            }else{
                
                modelContext.insert( PDFFile( url, bookmarkData, Date() ) )
                
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
    

    static func refreshLocations(_ modelContext: ModelContext, sync: LibrarySyncService) throws {
        
        try sync.requireReady()
        
        if LibrarySyncService.isEnabled(modelContext) {
            return
        }
        
        do {
        
            if try updateLocations( fetch(modelContext) ) {
                
                try modelContext.save()
                
            }
            
        } catch {
            
            modelContext.rollback()
            
            throw AppError.system("The library's file locations could not be updated before saving.", error.localizedDescription,error)
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
    
    static func delete(_ modelContext: ModelContext , _ url: URL, sync: LibrarySyncService) throws {
        
        try sync.requireReady()
        
        let fileURL = normalizedURL(url)
        
        if LibrarySyncService.isEnabled(modelContext) {
        
            do {
            
                for pdf in try fetch(modelContext) where normalizedURL(pdf.url) == fileURL {
                    
                    try sync.deletePDF(pdf, modelContext)
                    
                }
                
            } catch {
                modelContext.rollback();
                
                throw error
            
            }
            
            return
            
        }
        
        do{
            
            let matched = try fetch(modelContext).filter {
                normalizedURL($0.url) == fileURL
            }
            
            PDFTagService.deleteTagsOrphanedByDeleting(matched,  modelContext)

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
    
    
    static func deleteMissingFiles(_ modelContext: ModelContext,_ pdfFiles: [PDFFile], sync: LibrarySyncService, _ confirmedDeletedFileIDs: Set<PersistentIdentifier> = []) throws {

        if sync.state.isSwitching || LibrarySyncService.isEnabled(modelContext) {
            return
        }

        var needsSave = false

        let missingPDFFiles = pdfFiles.filter {
            $0.availability == .missing || (confirmedDeletedFileIDs.contains($0.persistentModelID) && FileIO.exists($0.resolvedURL) == false)
        }

        PDFTagService.deleteTagsOrphanedByDeleting(missingPDFFiles, modelContext )

        for pdfFile in missingPDFFiles {

            modelContext.delete(pdfFile)

            needsSave = true

        }

        if needsSave {
            do {
                try modelContext.save()
            } catch {

                modelContext.rollback()

                throw AppError.system( "The library could not be synchronized.", error.localizedDescription, error )
            }
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
            
            throw AppError.system("File access permissions could not be refreshed.", error.localizedDescription, error)
        }
    }
    
    private static func normalizedURL(_ url: URL) -> URL {
        
        let resolvedURL = url.resolvingSymlinksInPath()
        
        return resolvedURL.deletingLastPathComponent().resolvingSymlinksInPath()
            .appendingPathComponent(resolvedURL.lastPathComponent).standardizedFileURL
    }
    
    private static func fetch(_ modelContext:ModelContext) throws -> [PDFFile] {
        return try modelContext.fetch(FetchDescriptor<PDFFile>())
    }
}
