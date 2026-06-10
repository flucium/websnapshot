import Foundation
import SwiftData

final class PDFFileService {
    static func save( _ modelContext: ModelContext, _ url:URL) throws {
        
        let bookmarkData = URL.securityScopedBookmarkData(url)
        
        do{
            if let pdfFile = try fetch(modelContext).first(
                where: { $0.url == url
                }){
                                    
                if let bookmarkData {
                    pdfFile.bookmarkData = bookmarkData
                }
                            
                try modelContext.save()
                
            }else{
                modelContext.insert(PDFFile(url,  bookmarkData))
                                    
                try modelContext.save()
            }
            
        }catch{
            throw AppError.invalidIO("PDF file list save failed.")
        }
    }
    
    static func delete( _ modelContext: ModelContext , _ url: URL) throws {
        do {
            let matched = try fetch(modelContext).filter {
                $0.url == url
            }

            for entry in matched {
                modelContext.delete(entry)
            }

            if matched.isEmpty == false{
                try modelContext.save()
            }
               
        } catch {
            throw AppError.invalidIO("Delete PDF file list failed.")
        }
    }
    
    
    static func refreshBookmarks(in  pdfFileURLs: [URL], _ modelContext: ModelContext) throws {
           
        let pdfFilePaths = Set( pdfFileURLs.map{
            $0.standardizedFileURL.path
        })

        guard Set(pdfFileURLs.map{
            $0.standardizedFileURL.path
        }).isEmpty == false else {
            return
        }

        var needs = false
        
        do {
            for pdfFile in try fetch(modelContext) {
                let fileURL = pdfFile.resolvedURL
                 
                guard pdfFilePaths.contains(fileURL.deletingLastPathComponent().standardizedFileURL.path),
                       
                let bookmarkData = URL.securityScopedBookmarkData(fileURL)
                           
                else {
                    continue
                }

                pdfFile.bookmarkData = bookmarkData
                   
                needs = true
            }

            if needs {
                try modelContext.save()
            }
        } catch {
            throw AppError.invalidIO("Refreshing bookmarks failed.")
        }
    }
    
    private static func fetch(_ modelContext:ModelContext) throws -> [PDFFile] {
        return try modelContext.fetch(FetchDescriptor<PDFFile>())
    }
}
