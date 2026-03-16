//
//  HistoryView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import SwiftUI
import PDFKit
import SwiftData

struct HistoryView: View {
    @State private var selectedItem: HistoryEntry? = nil
    @State private var searchText: String = ""

    private var filteredItems: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return items
        }

        return items.filter {
            $0.fileName.localizedCaseInsensitiveContains(query)
        }
    }
    
    let items: [HistoryEntry]

    let onDelete: (HistoryEntry) -> Void

    var body: some View {
        Group {
            if let selectedItem {
                HistoryDetailView(item: selectedItem, onBack: closeDetail)
            } else {
                HistoryListContent(
                    searchText: $searchText,
                    items: filteredItems,
                    onOpen: open,
                    onDelete: delete
                )
            }
        }
    }
}

private extension HistoryView {
    func open(_ item: HistoryEntry) {
        selectedItem = item
    }

    func closeDetail() {
        selectedItem = nil
    }

    private func delete(_ item: HistoryEntry) {
        onDelete(item)
        try? deletePDFFile(url: item.fileURL)

        if selectedItem?.persistentModelID == item.persistentModelID {
            selectedItem = nil
        }
    }
}

private struct HistoryListContent: View {
    @Binding var searchText: String
    let items: [HistoryEntry]
    let onOpen: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void

    var body: some View {
        VStack {
            TextField("Search", text: $searchText)
                .padding()

            List {
                ForEach(items, id: \.persistentModelID) { item in
                    HistoryRow(item: item, onOpen: onOpen, onDelete: onDelete)
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let item: HistoryEntry
    let onOpen: (HistoryEntry) -> Void
    let onDelete: (HistoryEntry) -> Void

    var body: some View {
        Button {
            onOpen(item)
        } label: {
            Text(item.fileName)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                onDelete(item)
            }
        }
        .contextMenu {
            Button("Open PDF") {
                onOpen(item)
            }
            Button("Delete", role: .destructive) {
                onDelete(item)
            }
        }
    }
}

private struct HistoryDetailView: View {
    let item: HistoryEntry
    let onBack: () -> Void

    private var fileURL: URL {
        item.fileURL
    }

    var body: some View {
        VStack(spacing: 8) {
            header
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var header: some View {
        HStack {
            Button("Back", action: onBack)

            Text(item.fileName)
                .lineLimit(1)

            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var content: some View {
        if isPDFFile(url: fileURL) {
            HistoryPDFView(url: fileURL)
        } else {
            let error = AppError.notFound
            ContentUnavailableView(
                "Load failed: \(error.errorDescription ?? "unknown")",
                systemImage: "exclamationmark.triangle",
                description: Text(fileURL.path)
            )
        }
    }
}

private struct HistoryPDFView: View {
    let url: URL

    var body: some View {
        HistoryPDFPlatformView(url: url)
    }
}

#if os(macOS)
private struct HistoryPDFPlatformView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        configuredPDFView()
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        updatePDFDocument(for: nsView, url: url)
    }
}
#else
private struct HistoryPDFPlatformView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        configuredPDFView()
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        updatePDFDocument(for: uiView, url: url)
    }
}
#endif

private func configuredPDFView() -> PDFView {
    let view = PDFView()
    view.autoScales = true
    view.displayMode = .singlePageContinuous
    view.displayDirection = .vertical
    return view
}

private func updatePDFDocument(for view: PDFView, url: URL) {
    let data = withHistorySecurityScopedAccess(to: url) {
        try? Data(contentsOf: url)
    }

    view.document = data.flatMap(PDFDocument.init(data:))
}

private func withHistorySecurityScopedAccess<T>(to url: URL, action: () -> T) -> T {
#if os(macOS)
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
        if didAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
#endif
    return action()
}
