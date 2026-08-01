import Foundation

extension URL {
    static func securityScopedBookmarkData(_ url: URL) throws -> Data {
        let isAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveSecurityScopedBookmarkData(
        _ data: Data,
        _ isStale: inout Bool
    ) throws -> URL {
        try URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

}
