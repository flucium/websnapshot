//
//  PDFFileHistoryService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import SwiftData
import Foundation


enum PDFFileHistoryService {
    static func save(
        url: URL,
        modelContext: ModelContext,
        existingItems: [HistoryEntry]
    ) throws {
    
        guard !url.absoluteString.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard !existingItems.contains(where: { $0.fileURL == url }) else {
            return
        }

        
        modelContext.insert(
            HistoryEntry(
                url: url,
                bookmarkData: securityScopedBookmarkData(for: url)
            )
        )
        
        try modelContext.save()
    }

    static func record(
        url: URL,
        modelContext: ModelContext,
        existingItems: [HistoryEntry]
    ) -> AppError? {
        do {
            try save(
                url: url,
                modelContext: modelContext,
                existingItems: existingItems
            )
            return nil
        } catch {
            return AppError(error: error)
        }
    }

    private static func securityScopedBookmarkData(for url: URL) -> Data? {
#if os(macOS)
        return try? url.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
#else
        return nil
#endif
    }
}
