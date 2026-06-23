import Foundation

extension URL {
    static func securityScopedBookmarkData(_ url: URL) -> Data? {
        let isAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    static func resolveSecurityScopedBookmarkData(
        _ data: Data,
        bookmarkDataIsStale isStale: inout Bool
    ) -> URL? {
        try? URL(
            resolvingBookmarkData: data,
            options: [.withSecurityScope, .withoutUI],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

}
