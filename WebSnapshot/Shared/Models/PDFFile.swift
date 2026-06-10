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
        resolveBookmarkedURL(&bookmarkData) ?? url
    }
}


func resolveBookmarkedURL(_ bookmarkData: inout Data?) -> URL? {
    guard let data = bookmarkData else {
        return nil
    }

    var isStale = false

    guard let resolvedURL = try? URL(
        resolvingBookmarkData: data,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
    ) else {
        return nil
    }

    if isStale {
        bookmarkData = try? resolvedURL.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    return resolvedURL
}
