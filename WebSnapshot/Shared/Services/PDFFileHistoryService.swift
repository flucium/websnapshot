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

        
        modelContext.insert(HistoryEntry(url: url))
        
        try modelContext.save()
    }
}
