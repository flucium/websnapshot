import Foundation

extension URL{
    static func securityScopedBookmarkData(_ url: URL) -> Data? {
        defer {
            if url.startAccessingSecurityScopedResource() {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        return try? url.bookmarkData(options: [.withSecurityScope],includingResourceValuesForKeys: nil,relativeTo: nil)
    }
}
