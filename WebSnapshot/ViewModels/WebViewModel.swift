//
//  WebViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import Foundation
import WebKit
import Combine

@MainActor
class WebViewModel: ObservableObject {
    @Published var urlString: String = ""
    @Published var status: String = ""
    @Published var exportData: Data? = nil
    @Published var isExporting: Bool = false
    @Published var exportDocument: PDFFileDocument?

    var canExportPDF = false
    
    let webPage = WKWebView(frame: .zero)
    let errorState = ErrorState()
    let navigationDelegate = NavigationDelegate()
    

    init() {
        webPage.navigationDelegate = navigationDelegate

        navigationDelegate.onFinish = { [weak self] in
            guard let self else { return }
            self.canExportPDF = true
            self.errorState.clearError()
            self.status = ""
        }

        navigationDelegate.onError = { [weak self] message in
            guard let self else { return }
            self.canExportPDF = false
            self.errorState.setError(.display(message: "Load failed: \(message)"))
            self.status = "c"
        }
    }

    func load() {
        let input = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else {
            canExportPDF = false
            errorState.setError(.display(message: "Load failed"))
            status = errorState.status
            return
        }
        
        guard let url = URLUtilities().normalizedURL(from: input) else {
            canExportPDF = false
            errorState.setError(.invalidURL)
            status = errorState.status
            return
        }

        canExportPDF = false
        status = "Loading..."
        errorState.clearError()
        webPage.load(URLRequest(url: url))
    }

    func clear() {
        urlString = ""
        status = ""
        exportData = nil
        exportDocument = nil
        isExporting = false
        canExportPDF = false
        webPage.loadHTMLString("", baseURL: nil)
        errorState.clearError()
    }

   
}
