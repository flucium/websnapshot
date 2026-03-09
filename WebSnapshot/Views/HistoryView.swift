//
//  HistoryView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/07.
//

import SwiftUI
import PDFKit

struct HistoryView: View {

    @State private var selectedItem: PDFFileHistoryEntry? = nil
    @State private var searchText: String = ""

    let items: [PDFFileHistoryEntry]
    let onDelete: (PDFFileHistoryEntry) -> Void
    
    var body: some View {
        Group {
            if let selectedItem {
                historyPDFDetailView(for: selectedItem)
            } else {
                historyListView
            }
        }
    }

    private var historyListView: some View {
        VStack {
            TextField("Search", text: $searchText)
                .padding()
            List {
                ForEach(filteredItems, id: \.persistentModelID) { item in
                    Text(item.fileName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedItem = item
                        }
                        .contextMenu {
                            Button("Delete") {
                                onDelete(item)
                                do {
                                    try deletePDFFile(url: item.fileURL)
                                } catch {
                                    print(error)
                                }
                            }
                        }
                }
            }
        }
    }

    private var filteredItems: [PDFFileHistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }

        return items.filter {
            $0.fileName.localizedCaseInsensitiveContains(query)
        }
    }

    private func historyPDFDetailView(for item: PDFFileHistoryEntry) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button("Back") {
                    selectedItem = nil
                }

                Text(item.fileName)
                    .lineLimit(1)

                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 8)

            if isPDFFile(url: item.fileURL) {
                HistoryPDFView(url: item.fileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let error = AppError.notFound
                ContentUnavailableView(
                    "Load failed: \(error.errorDescription ?? "unknown")",
                    systemImage: "exclamationmark.triangle",
                    description: Text(item.fileURL.path)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

struct HistoryPDFView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        nsView.document = PDFDocument(url: url)
    }
}
