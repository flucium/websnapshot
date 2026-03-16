//
//  MultipleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

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
#if os(iOS)
        .fileImporter(
            isPresented: $multipleState.isSelectingSaveFolder,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderSelection
        )
#endif
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
                    Button("Save all PDFs", action: handleSaveAllPDFsTap)
                        .disabled(!multipleState.canExportPDF)
                    Button("Clear", action: multipleState.clear)

                    Text("Valid links: \(multipleState.validLinkCount)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                WebViewContainer(status: multipleState.status, font: .caption)
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

            WebPreview(webView: item.webView, height: 500, cornerRadius: 8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func configureState() {
        multipleState.setOnFileSaved { pdfURL in
            saveHistory(pdfURL: pdfURL)
        }
    }
    
    func saveHistory(pdfURL url: URL) {
        multipleState.recordHistory(
            url: url,
            modelContext: modelContext,
            existingItems: historyItems
        )
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

#if os(macOS)
    func handleSaveAllPDFsTap() {
        guard multipleState.canStartPDFExport() else { return }
        multipleState.status = "Choose a destination folder..."
        presentFolderSelectionPanelOnMac()
    }
#else
    func handleSaveAllPDFsTap() {
        multipleState.preparePDFExport()
    }
#endif

#if os(macOS)
    func presentFolderSelectionPanelOnMac() {
        let openPanel = NSOpenPanel()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.allowsMultipleSelection = false
        openPanel.canCreateDirectories = false
        openPanel.prompt = "Export"

        let response = openPanel.runModal()
        guard response == .OK, let folderURL = openPanel.url else {
            return
        }

        Task {
            await multipleState.saveAllPDFs(to: folderURL)
        }
    }
#endif
}

#Preview {
    MultipleView()
}
