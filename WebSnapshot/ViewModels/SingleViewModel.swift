//
//  SingleViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import SwiftUI
import WebKit

@MainActor
final class SingleViewModel: WebViewModel {
    
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
            self.errorState.clearError()
            self.status = ""
        }

        navigationDelegate.onError = { [weak self] message in
            self?.canExportPDF = false
            self?.errorState.setError(.display(message: "Load failed: \(message)"))
            self?.status = self?.errorState.status ?? "Load failed"
        }
    }

    override func clear() {
        isClearingWebView = true
        super.clear()
    }

    func save() {
        guard canExportPDF else {
            errorState.setError(.display(message: "No pages to save"))
            status = errorState.status
            return
        }

        errorState.clearError()
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
                    self.errorState.setError(.display(message: "Failed to export: \(error.localizedDescription)"))
                    self.status = "Failed to export"
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
