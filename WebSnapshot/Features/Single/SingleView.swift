//
//  SingleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import WebKit
#if os(macOS)
import AppKit
#endif

struct SingleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var singleState = SingleViewState()
    @Query private var historyItems: [HistoryEntry]

    var body: some View {
        content
#if os(iOS)
            .fileExporter(
                isPresented: $singleState.isExporting,
                document: singleState.pdfFileDocument,
                contentType: .pdf,
                defaultFilename: singleState.suggestedFileName(),
                onCompletion: handleExportResult
            )
#endif
    }
}

private extension SingleView {
    var content: some View {
        VStack(spacing: 8) {
            addressBar
            statusView
            webView
        }
    }

    var addressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                TextField("https://...", text: $singleState.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(singleState.load)

                Button("Load", action: singleState.load)
                Button("Save as PDF", action: saveAsPDF)
                    .disabled(!singleState.canTapSaveButton)
                Button("Clear", action: singleState.clear)
            }

//            if let errorMessage = singleState.errorMessage {
//                Text(errorMessage)
//                    .font(.caption)
//                    .foregroundStyle(.red)
//            }
        }
        .padding()
    }

    var statusView: some View {
        Text(singleState.status)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }

    var webView: some View {
        WebViewContainer(webView: singleState.wkWebView)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    func saveAsPDF() {
        Task {
            await singleState.saveAsPDF()
#if os(macOS)
            presentExportPanelOnMac()
#endif
        }
    }

#if os(macOS)
    func presentExportPanelOnMac() {
        guard let data = singleState.pdfFileDocument?.data else { return }

        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.pdf]
        savePanel.canCreateDirectories = true
        savePanel.prompt = "Export"
        savePanel.nameFieldStringValue = "\(singleState.suggestedFileName()).pdf"

        let response = savePanel.runModal()
        guard response == .OK, let destinationURL = savePanel.url else {
            return
        }

        do {
            try data.write(to: destinationURL, options: .atomic)
            handleExportResult(.success(destinationURL))
        } catch {
            handleExportResult(.failure(error))
        }
    }
#endif

    func handleExportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let savedURL):
            saveHistory(url: savedURL)
            singleState.status = "PDF exported"
        case .failure(let error):
            singleState
                .setError(
                    .display(
                        message: "Export failed: \(error.localizedDescription)"
                    )
                )
        }
    }
    
    func saveHistory(url: URL) {
        if let appError = PDFFileHistoryService.record(
            url: url,
            sourceURL: singleState.wkWebView.url,
            modelContext: modelContext,
            existingItems: historyItems
        ) {
            singleState.setError(appError)
        } else {
            singleState.clearError()
        }
    }
}

#Preview {
    SingleView()
}
