//
//  SingleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SingleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = SingleViewModel()
    @Query private var historyItems: [PDFHistoryEntry]

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("https://...", text: $viewModel.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        viewModel.load()
                    }

                Button("Load") {
                    viewModel.load()
                }

                Button("Save as PDF") {
                    viewModel.makePDFForExport()
                }

                Button("Clear") {
                    viewModel.clear()
                }
            }
            .padding()

            Text(viewModel.status)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            WebViewContainer(webView: viewModel.webPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileExporter(
            isPresented: $viewModel.isExporting,
            document: viewModel.exportDocument,
            contentType: .pdf,
            defaultFilename: viewModel.suggestedFileName()
        ) { result in
            switch result {
            case .success(let url):
                do {
                    try PDFHistoryStore.save(
                        path: url.path,
                        modelContext: modelContext,
                        existingItems: historyItems
                    )
                    viewModel.status = "Saved: \(url.lastPathComponent)"
                } catch {
                    viewModel.status = "History save failed: \(error.localizedDescription)"
                }

                viewModel.exportDocument = nil
                viewModel.isExporting = false

            case .failure(let error):
                viewModel.status = "Save failed: \(error.localizedDescription)"
                viewModel.exportDocument = nil
                viewModel.isExporting = false
            }
        }
    }
}

#Preview {
    SingleView()
}
