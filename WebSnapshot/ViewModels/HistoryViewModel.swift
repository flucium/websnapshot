//
//  HistoryViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import Foundation
import Combine
import SwiftData

@MainActor
final class HistoryViewModel: ObservableObject {
    @Published var selectedItem: PDFFileHistoryEntry? = nil
    @Published var searchText: String = ""

    func filteredItems(from items: [PDFFileHistoryEntry]) -> [PDFFileHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }

        return items.filter {
            $0.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    func select(_ item: PDFFileHistoryEntry) {
        selectedItem = item
    }

    func backToList() {
        selectedItem = nil
    }

    func delete(_ item: PDFFileHistoryEntry, onDelete: (PDFFileHistoryEntry) -> Void) {
        onDelete(item)

        if selectedItem?.persistentModelID == item.persistentModelID {
            selectedItem = nil
        }

        do {
            try deletePDFFile(url: item.fileURL)
        } catch {
            print(error)
        }
    }
}
