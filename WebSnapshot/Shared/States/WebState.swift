//
//  WebViewStatel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import Combine
import WebKit

@MainActor
class WebState: ObservableObject {
    @Published var urlString: String = ""
    @Published var status: String = ""
    @Published var appError: AppError? = nil
    @Published var pdfFileDocument: PDFFileDocument?
    @Published var isExporting: Bool = false
    
    private var isClearingWebView = false

    let navigationDelegate = NavigationDelegate()
    let wkWebView = WKWebView(frame: .zero)

    var hasInputURL: Bool {
        !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var errorMessage: String? {
        appError?.errorDescription
    }

    init() {
        wkWebView.navigationDelegate = navigationDelegate

        navigationDelegate.onFinish = { [weak self] in
            guard let self else { return }

            if self.isClearingWebView {
                self.isClearingWebView = false
                return
            }
            self.clearError()
            self.status = ""
        }

        navigationDelegate.onError = { [weak self] message in
            self?.setError(.display(message: "Load failed: \(message)"))
        }
    }

    func load() {
        guard let url = URL.normalizedWebURL(from: urlString) else {
            setError(.invalidURL)
            return
        }

        clearError()
        status = "Loading..."
        wkWebView.load(URLRequest(url: url))
    }

    func clear() {
        clearError()
        wkWebView.loadHTMLString("", baseURL: nil)
        pdfFileDocument = nil
        urlString = ""
        status = ""
        isClearingWebView = true
        isExporting = false
    }

    func setError(_ appError: AppError) {
        self.appError = appError
        status = appError.errorDescription ?? "unknown"
    }

    func setError(_ error: Error) {
        setError(AppError(error: error))
    }

    func clearError() {
        appError = nil
    }

    func makePDF(webView: WKWebView) async throws -> Data {
        try await pdfData(from: webView)
    }
}

private func pdfData(from webView: WKWebView) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        let config = WKPDFConfiguration()

        webView.createPDF(configuration: config) { result in
            switch result {
            case .success(let data):
                continuation.resume(returning: data)

            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}
