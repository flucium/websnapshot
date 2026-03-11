//
//  SingleState.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import Foundation
import WebKit


@MainActor
final class SingleViewState: WebState {
    var canTapSaveButton: Bool {
        !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func saveAsPDF() async {
        if let validationError = validateSaveRequest() {
            setError(validationError)
            return
        }

        clearError()
        pdfFileDocument = nil
        isExporting = false
        status = "Generating PDF..."

        do {
            let data = try await makePDF(webView: wkWebView)
            pdfFileDocument = PDFFileDocument(data: data)
            isExporting = true
            status = "PDF is ready"
        } catch {
            setError(.display(message: "Failed to generate PDF: \(error.localizedDescription)"))
        }
    }

    func suggestedFileName() -> String {
        let rawTitle = wkWebView.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = rawTitle.components(separatedBy: invalid).joined()

        if !cleaned.isEmpty {
            return cleaned
        }

        if let currentURL = wkWebView.url {
            return URL.filename(for: currentURL).replacingOccurrences(of: ".pdf", with: "")
        }

        return "page"
    }

    private func validateSaveRequest() -> AppError? {
        let trimmedInput = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInput.isEmpty else {
            return .display(message: "URL is empty. Load a page first.")
        }

        guard let loadedURL = wkWebView.url, isHTTPURL(loadedURL) else {
            return .display(message: "No website is loaded. Load a page first.")
        }

        guard !wkWebView.isLoading else {
            return .display(message: "Page is still loading. Try again after it finishes.")
        }

        return nil
    }

    private func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}
