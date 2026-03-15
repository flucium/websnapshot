//
//  HistoryView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import SwiftUI
import PDFKit
import WebKit
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
                    Button {
                        selectedItem = item
                        
                    } label: {
                        Text(item.fileName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) {
                        selectedItem = item
                        
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive) {
                            delete(item)
                        }
                    }
                    .contextMenu {
                        Button("Open PDF") {
                            selectedItem = item
                        }
//                        if item.sourceURL != nil {
//                            Button("Open Web") {
//                                selectedItem = item
//                                previewMode = .web
//                            }
//                        }
                        Button("Delete", role: .destructive) {
                            delete(item)
                        }
                    }
                }
            }
        }
    }



    private func historyPDFDetailView(for item: HistoryEntry) -> some View {
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


            Group {
                if isPDFFile(url: item.fileURL) {
                    HistoryPDFView(url: item.fileURL)
                } else {
                    let error = AppError.notFound
                    ContentUnavailableView(
                        "Load failed: \(error.errorDescription ?? "unknown")",
                        systemImage: "exclamationmark.triangle",
                        description: Text(item.fileURL.path)
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func delete(_ item: HistoryEntry) {
        onDelete(item)
        do {
            try deletePDFFile(url: item.fileURL)
        } catch {
            //
        }

        if selectedItem?.persistentModelID == item.persistentModelID {
            selectedItem = nil
            
        }
    }
}

struct HistoryPDFView: View {
    let url: URL

    var body: some View {
        HistoryPDFPlatformView(url: url)
    }
}

#if os(macOS)
private struct HistoryPDFPlatformView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            nsView.document = nil
            return
        }

        nsView.document = PDFDocument(data: data)
    }
}
#else
private struct HistoryPDFPlatformView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        guard let data = try? Data(contentsOf: url) else {
            uiView.document = nil
            return
        }

        uiView.document = PDFDocument(data: data)
    }
}
#endif

private struct HistoryWebView: View {
    let url: URL
    @State private var webView = WKWebView()

    var body: some View {
        WebViewContainer(webView: webView)
            .task(id: url) {
                webView.load(URLRequest(url: url))
            }
    }
}
