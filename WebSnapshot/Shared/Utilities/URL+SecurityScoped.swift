import Foundation

extension URL {
    nonisolated static func securityScopedBookmarkData(_ url: URL) throws -> Data {
        let isAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    nonisolated static func resolveSecurityScopedBookmarkData(_ data: Data,_ isStale: inout Bool) throws -> URL {
        try URL( resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &isStale)
    }

    nonisolated static func bookmarkTargetIsMissing(_ data: Data, _ error: Error) -> Bool {
        if FileIO.isMissingFileError(error) {
            return true
        }

        let error = error as NSError
        
        return error.domain == NSCocoaErrorDomain && error.code == CocoaError.fileReadCorruptFile.rawValue &&
            NSURL.resourceValues(forKeys: [.nameKey], fromBookmarkData: data) != nil
    }

}
