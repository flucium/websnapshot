//
//  PDFHistoryStore.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/07.
//

import Foundation
import SwiftData

enum PDFHistoryStore {
    static func save(
        path: String,
        modelContext: ModelContext,
        existingItems: [PDFHistoryEntry]
    ) throws {
        if existingItems.contains(where: { $0.path == path }) {
            return
        }

        let entry = PDFHistoryEntry(path: path)
        modelContext.insert(entry)
        try modelContext.save()
    }

    static func delete(
        _ item: PDFHistoryEntry,
        modelContext: ModelContext
    ) throws {
        modelContext.delete(item)
        try modelContext.save()
    }
}
