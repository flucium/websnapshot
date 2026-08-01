import Foundation
import SwiftData

@Model
final class PDFFile {
    var url: URL
    var bookmarkData: Data?
    
    init(
        _ url: URL,
        _ bookmarkData:Data? = nil
    ) {
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

extension PDFFile {
    var resolvedURL: URL {
        guard let bookmarkData else {
            return url
        }
        
        do {
            return try resolveBookmarkedURL(
                bookmarkData
            )
        } catch {
            AppLogger
                .record(
                    AppError(
                        error
                    ),
                    "Resolve security-scoped bookmark",
                    url
                )
            return url
        }
    }
}


func resolveBookmarkedURL(
    _ data: Data
) throws -> URL {
    var isStale = false
    
    let resolvedURL = try URL.resolveSecurityScopedBookmarkData(
        data,
        &isStale
    )
    
    if isStale {
        AppLogger
            .recordDiagnostic(
            "The security-scoped bookmark is stale.",
            "Resolve security-scoped bookmark",
            resolvedURL
        )
    }

    return resolvedURL
}
