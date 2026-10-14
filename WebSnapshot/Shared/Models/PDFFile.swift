import Foundation
import SwiftData

@Model
final class PDFFile {
    var url: URL
    
    var bookmarkData: Data?
    
    var addedAt: Date? = nil
    
    var tags: [PDFTag] = []
    
    var searchableText: String? = nil
    
    var contentFingerprint: String? = nil

    var libraryID: UUID? = nil

    var syncRelativePath: String? = nil

    var syncContentHash: String? = nil

    var syncBaselineTags: Data? = nil

    var syncBaselineContentHash: String? = nil
    
    init(_ url: URL,_ bookmarkData:Data? = nil, _ addedAt: Date? = nil) {
    
        self.url = url
        
        self.bookmarkData = bookmarkData
        
        self.addedAt = addedAt
    }
}

extension PDFFile {
    func resolveURL() throws -> URL {
        
        guard let bookmarkData else {
            
            return url
            
        }
        
        return try resolveBookmarkedURL(bookmarkData)
    }

    var availability: FileIO.Availability {
        
        if syncRelativePath != nil {
        
            let file = resolvedURL
            
            let accessing = file.startAccessingSecurityScopedResource()
            
            defer {
            
                if accessing {
                    file.stopAccessingSecurityScopedResource()
                }
                
            }
            
            let values = try? file.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            
            if values?.ubiquitousItemDownloadingStatus == .notDownloaded {
            
                return .unavailable
                
            }
            
            return FileIO.availability(file) == .available ? .available : .unavailable
        }
        
        do {
            return FileIO.availability( try resolveURL() )
        } catch {
            
            if FileIO.isMissingFileError(error) {
                return FileIO.availability(url)
            }
            
            return .unavailable
        }
    }

    var resolvedURL: URL {
        
        do {
        
            return try resolveURL()
            
        } catch {
            
            AppLogger.record(AppError(error), "Resolve security-scoped bookmark", url)
            
            return url
        }
    }
}


func resolveBookmarkedURL(_ data: Data) throws -> URL {
    var isStale = false
    
    let resolvedURL = try URL.resolveSecurityScopedBookmarkData(data,&isStale)
    
    if isStale {
        AppLogger.recordDiagnostic("The security-scoped bookmark is stale.","Resolve security-scoped bookmark",resolvedURL)
    }

    return resolvedURL
}
