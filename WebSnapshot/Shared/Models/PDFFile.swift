import Foundation
import SwiftData

@Model
final class PDFFile {
    var url: URL
    var bookmarkData: Data?
    var tags: [PDFTag] = []
    
    init(
        _ url: URL,
        _ bookmarkData:Data? = nil
    ) {
        self.url = url
        self.bookmarkData = bookmarkData
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
        do {
            return FileIO.availability(try resolveURL())
        } catch {
            // A deleted bookmark target is different from an invalid bookmark or denied access.
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
