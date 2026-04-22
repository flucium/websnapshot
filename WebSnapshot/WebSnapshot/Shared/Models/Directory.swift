
import Foundation
import SwiftData

@Model
final class Directory {
    var url: URL
    var bookmarkData: Data?
    
    init(_ url: URL, _ bookmarkData:Data? = nil) {
        self.url = url
        self.bookmarkData = bookmarkData
    }
}


extension Directory {
    var resolvedURL: URL {
        resolvedBookmarkedURL ?? url
    }

    private var resolvedBookmarkedURL: URL? {
        
        guard let bookmarkData else {
            return nil
        }

        var isStale = false
        
        guard let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData,options: [.withSecurityScope],relativeTo: nil,bookmarkDataIsStale: &isStale) else {
            return nil
        }

        if isStale {
            self.bookmarkData = try? resolvedURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        return resolvedURL
    }
}


@Model
final class DirectoryHistory {
    var url: URL
    var bookmarkData: Data?
    var usedAt:Date
    
    init(_ url: URL, _ bookmarkData: Data? = nil, usedAt:Date) {
        self.url = url
        self.bookmarkData = bookmarkData
        self.usedAt = usedAt
    }
}


extension DirectoryHistory {
    var resolvedURL: URL {
        resolvedBookmarkedURL ?? url
    }

    private var resolvedBookmarkedURL: URL? {
        
        guard let bookmarkData else {
            return nil
        }

        var isStale = false
        
        guard let resolvedURL = try? URL(resolvingBookmarkData: bookmarkData, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale ) else {
            return nil
        }

        if isStale {
            self.bookmarkData = try? resolvedURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        }

        return resolvedURL
    }
}
