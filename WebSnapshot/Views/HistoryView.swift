//
//  HistoryView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import SwiftUI
import PDFKit

struct HistoryView: View {
    @StateObject private var historyViewModel = HistoryViewModel()

    let items: [PDFFileHistoryEntry]
    let onDelete: (PDFFileHistoryEntry) -> Void
    
    var body: some View {
        Group {
            if let selectedItem = historyViewModel.selectedItem {
                historyPDFDetailView(for: selectedItem)
            } else {
                historyListView
            }
        }
    }

    private var historyListView: some View {
        VStack {
            TextField("Search", text: $historyViewModel.searchText)
                .padding()
            List {
                ForEach(historyViewModel.filteredItems(from: items), id: \.persistentModelID) { item in
                    Text(item.fileName)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            historyViewModel.select(item)
                        }
                        .contextMenu {
                            Button("Delete") {
                                historyViewModel.delete(item, onDelete: onDelete)
                            }
                        }
                }
            }
        }
    }

    private func historyPDFDetailView(for item: PDFFileHistoryEntry) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button("Back") {
                    historyViewModel.backToList()
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
