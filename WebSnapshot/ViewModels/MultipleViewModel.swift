//
//  MultipleViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//


import Foundation
import WebKit
import Combine

@MainActor
final class MultipleViewModel: WebViewModel {

    @Published var linkText: String = ""
    @Published var items: [WebItem] = []

    var onFileSaved: ((URL) -> Void)?

    func loadLinks() {
        let urls = parseURLs(from: linkText)
        items = urls.map { WebItem(url: $0) }
    }

    func clear() {
        linkText = ""
        items = []
        status = ""
    }

    func makePDFsForExport() {
        guard !items.isEmpty else {
            status = "No pages to save"
            return
        }

        status = "Rendering PDFs..."

        chooseDirectory { [weak self] folderURL in
            guard let self else { return }

            guard let folderURL else {
                DispatchQueue.main.async {
                    self.status = "Export cancelled"
                }
                return
            }

            Task {
                do {
                    for (index, item) in self.items.enumerated() {
                        let data = try await self.createPDFData(from: item.webView)
                        let fileURL = folderURL.appendingPathComponent(
                            self.filename(for: item.url, index: index)
                        )

                        try data.write(to: fileURL)

                        await MainActor.run {
                            self.onFileSaved?(fileURL)
                            self.status = "Saved \(index + 1)/\(self.items.count)"
                        }
                    }

                    await MainActor.run {
                        self.status = "All PDFs saved"
                    }
                } catch {
                    await MainActor.run {
                        self.status = "PDF export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func parseURLs(from text: String) -> [URL] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { normalizedURL(from: $0) }
    }
}
