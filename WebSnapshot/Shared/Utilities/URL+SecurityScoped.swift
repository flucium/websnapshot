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
            options: securityScopedBookmarkCreationOptions,
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
            options: securityScopedBookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }

    private static var securityScopedBookmarkCreationOptions: BookmarkCreationOptions {
#if os(macOS)
        [.withSecurityScope]
#else
        []
#endif
    }

    private static var securityScopedBookmarkResolutionOptions: BookmarkResolutionOptions {
#if os(macOS)
        [.withSecurityScope, .withoutUI]
#else
        [.withoutUI]
#endif
    }
}
