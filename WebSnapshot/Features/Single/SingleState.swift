//
//  SingleState.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import Foundation
import WebKit


@MainActor
final class SingleState: WebState {
    var canExportPDF: Bool {
        hasInputURL
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
            let data = try await makePDF()
            pdfFileDocument = PDFFileDocument(data: data)
#if os(iOS)
            isExporting = true
#else
            isExporting = false
#endif
            status = "PDF is ready"
        } catch {
            setError(.display(message: "Failed to generate PDF: \(error.localizedDescription)"))
        }
    }

    func suggestedFileName() -> String {
        URL.pdfBaseName(
            title: wkWebView.title,
            fallbackURL: wkWebView.url
        )
    }

    private func validateSaveRequest() -> AppError? {
        guard hasInputURL else {
            return .display(message: "URL is empty. Load a page first.")
        }

        guard let loadedURL = wkWebView.url, loadedURL.isSupportedWebURL else {
            return .display(message: "No website is loaded. Load a page first.")
        }

        guard !wkWebView.isLoading else {
            return .display(message: "Page is still loading. Try again after it finishes.")
        }

        return nil
    }
}
