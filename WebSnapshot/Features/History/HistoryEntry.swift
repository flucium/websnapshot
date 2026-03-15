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
    var sourceURL: URL?
    var bookmarkData: Data?

    init(url: URL, sourceURL: URL? = nil, bookmarkData: Data? = nil) {
        self.url = url
        self.sourceURL = sourceURL
        self.bookmarkData = bookmarkData
    }
}

extension HistoryEntry {
    var fileURL: URL {
        resolvedBookmarkedURL ?? url
    }

    private var resolvedBookmarkedURL: URL? {
#if os(macOS)
        if let bookmarkData {
            var isStale = false
            if let resolvedURL = try? URL(
                resolvingBookmarkData: bookmarkData,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            ) {
                if isStale {
                    self.bookmarkData = try? resolvedURL.bookmarkData(
                        options: [.withSecurityScope],
                        includingResourceValuesForKeys: nil,
                        relativeTo: nil
                    )
                }
                return resolvedURL
            }
        }
#endif
        return nil
    }

    var fileName: String {
        URL.displayPDFFileName(fileURL: fileURL, sourceURL: sourceURL)
    }
}
