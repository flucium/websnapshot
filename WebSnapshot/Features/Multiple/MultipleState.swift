//
//  MultipleViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import Foundation
import Combine
import WebKit

@MainActor
final class MultipleState: WebState {
    @Published private(set) var items: [WebItem] = []
    @Published var isSelectingSaveFolder = false

    var onFileSaved: ((URL) -> Void)?

    var validLinkCount: Int {
        items.count
    }

    var canTapSaveButton: Bool {
        hasInputURL && parsedInput.invalidLineNumbers.isEmpty
    }

    override func load() {
        guard let urls = validatedInputURLs() else {
            return
        }

        items = urls.map { WebItem(url: $0) }
        status = "Loaded \(items.count) links"
    }

    override func clear() {
        urlString = ""
        items = []
        isSelectingSaveFolder = false
        clearError()
        status = ""
    }

    func preparePDFExport() {
        guard let urls = validatedInputURLs() else {
            return
        }

        guard !items.isEmpty else {
            setError(.display(message: "No loaded pages to save. Press Load first."))
            return
        }

        guard items.count == urls.count else {
            setError(.display(message: "Links changed. Press Load again before saving."))
            return
        }

        clearError()
        status = "Choose a destination folder..."
        isSelectingSaveFolder = true
    }

    func setOnFileSaved(_ handler: @escaping (URL) -> Void) {
        onFileSaved = handler
    }

    func saveAllPDFs(to folderURL: URL) async {
        guard !items.isEmpty else {
            setError(.display(message: "No pages to save"))
            return
        }

        guard folderURL.startAccessingSecurityScopedResource() else {
            setError(.display(message: "Cannot access selected folder"))
            return
        }

        clearError()
        status = "Saving \(items.count) PDFs..."

        do {
            for (index, item) in items.enumerated() {
                guard !item.webView.isLoading else {
                    throw AppError.display(message: "Some pages are still loading. Try again in a moment.")
                }

                let data = try await makePDF(webView: item.webView)
                let defaultFileName = suggestedPDFFileName(for: item, index: index + 1)
                let destinationURL = uniqueDestinationURL(
                    in: folderURL,
                    defaultFileName: defaultFileName
                )

                try data.write(to: destinationURL, options: .atomic)
                onFileSaved?(destinationURL)

                let savedCount = index + 1
                status = savedCount == items.count
                    ? "Saved \(savedCount) PDFs"
                    : "Saved \(savedCount)/\(items.count)"
            }
        } catch {
            setError(AppError(error: error))
        }
    }

    private var parsedInput: (urls: [URL], invalidLineNumbers: [Int]) {
        URL.parseWebURLs(from: urlString)
    }

    private func validatedInputURLs() -> [URL]? {
        guard hasInputURL else {
            setError(.display(message: "Enter at least one link."))
            return nil
        }

        let parsed = parsedInput
        guard parsed.invalidLineNumbers.isEmpty else {
            setError(.display(message: invalidLinesMessage(from: parsed.invalidLineNumbers)))
            return nil
        }

        guard !parsed.urls.isEmpty else {
            setError(.display(message: "Enter at least one valid link."))
            return nil
        }

        clearError()
        return parsed.urls
    }

    private func invalidLinesMessage(from lineNumbers: [Int]) -> String {
        let display = lineNumbers.prefix(3).map(String.init).joined(separator: ", ")
        let suffix = lineNumbers.count > 3 ? "..." : ""
        return "Invalid link: line \(display)\(suffix)"
    }

    private func uniqueDestinationURL(in folderURL: URL, defaultFileName: String) -> URL {
        let fileManager = FileManager.default
        let ext = (defaultFileName as NSString).pathExtension
        let baseName = (defaultFileName as NSString).deletingPathExtension
        var candidate = folderURL.appendingPathComponent(defaultFileName)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(baseName)-\(counter)" : "\(baseName)-\(counter).\(ext)"
            candidate = folderURL.appendingPathComponent(nextName)
            counter += 1
        }

        return candidate
    }

    private func suggestedPDFFileName(for item: WebItem, index: Int) -> String {
        URL.pdfFileName(
            title: item.webView.title,
            fallbackURL: item.url,
            fallbackPrefix: "page-\(index)"
        )
    }
}
