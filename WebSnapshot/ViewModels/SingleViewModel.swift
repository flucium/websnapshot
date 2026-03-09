//
//  SingleViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import Foundation
import WebKit
import Combine

@MainActor
final class SingleViewModel: WebViewModel {

    @Published var urlString: String = "https://example.com"
    @Published var exportData: Data? = nil
    @Published var isExporting: Bool = false
    @Published var exportDocument: PDFFileDocument?

    let webPage = WKWebView(frame: .zero)

    private let navigationDelegate = NavigationDelegate()
    private var canExportPDF = false
    private var isClearingWebView = false

    override init() {
        super.init()

        webPage.navigationDelegate = navigationDelegate

        navigationDelegate.onFinish = { [weak self] in
            guard let self else { return }

            if self.isClearingWebView {
                self.isClearingWebView = false
                self.canExportPDF = false
                return
            }

            self.canExportPDF = true
            self.clearError()
            self.status = ""
        }

        navigationDelegate.onError = { [weak self] message in
            self?.canExportPDF = false
            self?.setError(.display(message: "Load failed: \(message)"))
        }
    }

    func load() {
        guard let url = normalizedURL(from: urlString) else {
            setError(.invalidURL)
            return
        }

        canExportPDF = false
        clearError()
        status = "Loading..."
        webPage.load(URLRequest(url: url))
    }

    func clear() {
        urlString = ""
        clearError()
        status = ""
        exportData = nil
        exportDocument = nil
        isExporting = false
        canExportPDF = false
        isClearingWebView = true
        webPage.loadHTMLString("", baseURL: nil)
    }

    func makePDFForExport() {
        guard canExportPDF else {
            setError(.display(message: "No pages to save"))
            return
        }
        
        clearError()
        status = "Rendering PDF..."

        let config = WKPDFConfiguration()

        webPage.createPDF(configuration: config) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let data):
                DispatchQueue.main.async {
                    self.exportData = data
                    self.exportDocument = PDFFileDocument(data: data)
                    self.isExporting = true
                    self.status = "Ready to export"
                }

            case .failure(let error):
                DispatchQueue.main.async {
                    self.exportDocument = nil
                    self.isExporting = false
                    self.setError(error)
                }
            }
        }
    }

    func suggestedFileName() -> String {
        let rawTitle = webPage.title ?? "page"
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = rawTitle.components(separatedBy: invalid).joined()

        return cleaned.isEmpty ? "page" : cleaned
    }
}
