//
//  MultipleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct MultipleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var multipleState = MultipleState()

    @State private var isLinksExpanded = true
    @State private var isWebExpanded = true

    @Query private var historyItems: [HistoryEntry]

    var body: some View {
        ScrollView {
            content
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .fileImporter(
            isPresented: $multipleState.isSelectingSaveFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderSelection
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear(perform: configureState)
    }
}

private extension MultipleView {
    var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            linksSection
            webSection
            Spacer(minLength: 0)
        }
    }

    var linksSection: some View {
        DisclosureGroup("Links", isExpanded: $isLinksExpanded) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Enter one link per line")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextEditor(text: $multipleState.urlString)
                    .frame(height: 140)
                    .padding(6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(.separator, lineWidth: 1)
                    )

                HStack {
                    Button("Load", action: multipleState.load)
                    Button("Save all PDFs", action: multipleState.preparePDFExport)
                        .disabled(!multipleState.canTapSaveButton)
                    Button("Clear", action: multipleState.clear)

                    Text("Valid links: \(multipleState.validLinkCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage = multipleState.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }

                Text(multipleState.status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 8)
        }
    }

    var webSection: some View {
        DisclosureGroup("Web", isExpanded: $isWebExpanded) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(multipleState.items) { item in
                    webItemView(item)
                }
            }
            .padding(.top, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    func webItemView(_ item: WebItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.url.absoluteString)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)

            WebViewContainer(webView: item.webView)
                .frame(maxWidth: .infinity)
                .frame(height: 500)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func configureState() {
        multipleState.setOnFileSaved { url in
            saveHistory(url: url)
        }
    }
    
    func saveHistory(url: URL) {
        if let appError = PDFFileHistoryService.record(
            url: url,
            modelContext: modelContext,
            existingItems: historyItems
        ) {
            multipleState.setError(appError)
        } else {
            multipleState.clearError()
        }
    }

    func handleFolderSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let folderURL = urls.first else {
                multipleState.setError(.display(message: "No folder selected"))
                return
            }
            Task {
                await multipleState.saveAllPDFs(to: folderURL)
            }
        case .failure(let error):
            multipleState.setError(.display(message: "Folder selection failed: \(error.localizedDescription)"))
        }
    }
}

#Preview {
    MultipleView()
}
