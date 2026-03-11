//
//  SingleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI
import UniformTypeIdentifiers

struct SingleView: View {
    @StateObject private var singleState = SingleViewState()

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
        HStack {
            TextField("https://...", text: $singleState.urlString)
                .textFieldStyle(.roundedBorder)
                .onSubmit(singleState.load)

            Button("Load", action: singleState.load)
            Button("Save as PDF", action: saveAsPDF)
                .disabled(!singleState.canTapSaveButton)
            Button("Clear", action: singleState.clear)
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
        case .success:
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
}

#Preview {
    SingleView()
}
