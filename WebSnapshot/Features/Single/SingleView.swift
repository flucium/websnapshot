//
//  SingleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SingleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var singleState = SingleViewState()
    @Query private var historyItems: [HistoryEntry]

    var body: some View {
        content
            .fileExporter(
                isPresented: $singleState.isExporting,
                document: singleState.pdfFileDocument,
                contentType: .pdf,
                defaultFilename: singleState.suggestedFileName(),
                onCompletion: handleExportResult
            )
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

            if let errorMessage = singleState.errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
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
        }
    }

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
