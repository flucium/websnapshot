//
//  PDFFileHistoryService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import SwiftData
import Foundation


enum PDFFileHistoryService {
    static func save(
        url: URL,
        modelContext: ModelContext,
        existingItems: [PDFFileHistoryEntry]
    ) throws {
    
        guard !url.absoluteString.isEmpty else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard !existingItems.contains(where: { $0.fileURL == url }) else {
            return
        }

        
        modelContext.insert(PDFFileHistoryEntry(url: url))
        
        try modelContext.save()
    }
}
