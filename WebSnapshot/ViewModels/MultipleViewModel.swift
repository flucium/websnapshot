//
//  MultipleViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import Foundation
import WebKit
import Combine

@MainActor
final class MultipleViewModel: WebViewModel {
    @Published var linkText: String = ""
    @Published var items: [WebItem] = []

    var onFileSaved: ((URL) -> Void)?
    private let pdfService = PDFService()

    override func load() {
        let urls = parseURLs(from: linkText)
        guard !urls.isEmpty else {
            items = []
            errorState.setError(.display(message: "Load failed"))
            status = errorState.status
            return
        }

        errorState.clearError()
        status = ""
        items = urls.map { WebItem(url: $0) }
    }


    override func clear() {
        for item in items {
            item.webView.stopLoading()
            item.webView.loadHTMLString("", baseURL: nil)
        }

        linkText = ""
        items = []
        status = ""
        exportData = nil
        exportDocument = nil
        isExporting = false
        canExportPDF = false
        errorState.clearError()
    }

    func save() {
        guard !items.isEmpty else {
            errorState.setError(.display(message: "No pages to save"))
            status = errorState.status
            return
        }

        let saveDirectory: URL

//#if os(macOS)
        guard let selectedDirectory = DirectoryChooserDialog.choose() else {
            status = "Save canceled"
            return
        }
        saveDirectory = selectedDirectory
//#else
//        errorState.setError(.display(message: "Multiple save is not supported on this platform"))
//        status = errorState.status
//        return
//#endif

        errorState.clearError()
        status = "Rendering PDFs..."

        Task { [weak self] in
            guard let self else { return }
            await self.renderAndSaveAll(to: saveDirectory)
        }
    }

    private func parseURLs(from text: String) -> [URL] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { URLUtilities().normalizedURL(from: $0) }
    }

    private func renderAndSaveAll(to directory: URL) async {
        var savedCount = 0
        var failedCount = 0

        for (index, item) in items.enumerated() {
            status = "Rendering PDFs... (\(index + 1)/\(items.count))"

            do {
                try await waitUntilLoaded(item.webView)
                let pdfData = try await pdfService.pdfData(from: item.webView)

                let fileName = URLUtilities().makePDFFileName(for: item.url)
                let destination = uniqueDestinationURL(in: directory, fileName: fileName)
                try pdfData.write(to: destination, options: .atomic)

                savedCount += 1
                onFileSaved?(destination)
            } catch {
                failedCount += 1
            }
        }

        if failedCount == 0 {
            status = "Saved \(savedCount) files"
            return
        }

        if savedCount == 0 {
            errorState.setError(.display(message: "Failed to save all files"))
            status = errorState.status
            return
        }

        errorState.setError(.display(message: "Saved \(savedCount) files, failed \(failedCount)"))
        status = "Completed with errors"
    }

    private func uniqueDestinationURL(in directory: URL, fileName: String) -> URL {
        let fileManager = FileManager.default
        let fileExtension = (fileName as NSString).pathExtension
        let baseName = (fileName as NSString).deletingPathExtension

        var candidate = directory.appendingPathComponent(fileName)
        var suffix = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let numberedName: String
            if fileExtension.isEmpty {
                numberedName = "\(baseName)-\(suffix)"
            } else {
                numberedName = "\(baseName)-\(suffix).\(fileExtension)"
            }
            candidate = directory.appendingPathComponent(numberedName)
            suffix += 1
        }

        return candidate
    }
}

private final class WebLoadObserver: NSObject, WKNavigationDelegate {
    private var continuation: CheckedContinuation<Void, Error>?

    func wait(for webView: WKWebView) async throws {
        if !webView.isLoading {
            return
        }

        try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            webView.navigationDelegate = self
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume()
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error)
        continuation = nil
    }
}

@MainActor
private func waitUntilLoaded(_ webView: WKWebView) async throws {
    let observer = WebLoadObserver()
    try await observer.wait(for: webView)
}
