//
//  HistoryEntry.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import SwiftData

@Model
final class HistoryEntry {
    var url: URL
    var bookmarkData: Data?

    init(url: URL, bookmarkData: Data? = nil) {
        self.url = url
        self.bookmarkData = bookmarkData
    }
}

extension HistoryEntry {
    var fileURL: URL {
        resolvedBookmarkURL() ?? url
    }

    var fileName: String {
        URL.displayPDFFileName(fileURL: fileURL)
    }

    private func resolvedBookmarkURL() -> URL? {
        guard let bookmarkData else {
            return nil
        }

        var isStale = false
        guard let resolvedURL = try? URL(
            resolvingBookmarkData: bookmarkData,
            options: URL.historyBookmarkResolutionOptions,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }

        refreshBookmarkDataIfNeeded(for: resolvedURL, isStale: isStale)
        return resolvedURL
    }

    private func refreshBookmarkDataIfNeeded(for url: URL, isStale: Bool) {
        guard isStale else {
            return
        }

        bookmarkData = try? url.bookmarkData(
            options: URL.historyBookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }
}

private extension URL {
    static var historyBookmarkCreationOptions: BookmarkCreationOptions {
#if os(macOS)
        [.withSecurityScope]
#else
        []
#endif
    }

    static var historyBookmarkResolutionOptions: BookmarkResolutionOptions {
#if os(macOS)
        [.withSecurityScope]
#else
        []
#endif
    }
}
