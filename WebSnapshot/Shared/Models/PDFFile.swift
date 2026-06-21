import Foundation
import SwiftData

@Model
final class PDFFile {
    var url: URL
    var bookmarkData: Data?
    
    init(_ url: URL, _ bookmarkData:Data? = nil) {
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

extension PDFFile {
    var resolvedURL: URL {
        resolveBookmarkedURL(bookmarkData) ?? url
    }
}


func resolveBookmarkedURL(_ bookmarkData: Data?) -> URL? {
    guard let data = bookmarkData else {
        return nil
    }

    var isStale = false

    return URL.resolveSecurityScopedBookmarkData(
        data,
        bookmarkDataIsStale: &isStale
    )
}
