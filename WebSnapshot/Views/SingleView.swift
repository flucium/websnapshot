//
//  SingleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import SwiftUI
import WebKit
import UniformTypeIdentifiers

struct SingleView: View {
    @StateObject private var viewModel = SingleViewModel()

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
            document: viewModel.exportData.map { PDFFileDocument(data: $0) },
            contentType: .pdf,
            defaultFilename: viewModel.suggestedFileName()
        ) { result in
            switch result {
            case .success(let url):
                viewModel.status = "Saved: \(url.path)"
            case .failure(let error):
                viewModel.status = "Save failed: \(error.localizedDescription)"
            }

            viewModel.exportDocument = nil
        }
    }
}
