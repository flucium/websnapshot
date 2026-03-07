//
//  HistoryView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/07.
//

import SwiftUI
import PDFKit

struct HistoryView: View {

    @State private var selectedItem: PDFHistoryEntry? = nil

    let items: [PDFHistoryEntry]
    let onDelete: (PDFHistoryEntry) -> Void
    
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
        List {
            ForEach(items, id: \.persistentModelID) { item in
                Text(item.fileName)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        selectedItem = item
                    }
                    .contextMenu {
                        Button("Delete") {
                            onDelete(item)
                            deletePDFFile(path: item.path)
                        }
                    }
            }
        }
    }

    private func historyPDFDetailView(for item: PDFHistoryEntry) -> some View {
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

            if FileManager.default.fileExists(atPath: item.path) {
                HistoryPDFView(url: item.fileURL)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "File Not Found.",
                    systemImage: "exclamationmark.triangle",
                    description: Text(item.path)
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
