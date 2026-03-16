//
//  WebViewStatel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import Foundation
import Combine
import CoreGraphics
import SwiftData
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
    let wkWebView = makeWebView()

    var trimmedURLString: String {
        urlString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var hasInputURL: Bool {
        !trimmedURLString.isEmpty
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
        guard let url = URL.normalizedWebURL(from: trimmedURLString) else {
            setError(.invalidURL)
            return
        }

        clearError()
        status = "Loading..."
        wkWebView.load(URLRequest(url: url))
    }

    func clear() {
        resetCommonState()
        clearLoadedPage()
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

    func makePDF(from webView: WKWebView? = nil) async throws -> Data {
        try await pdfData(from: webView ?? wkWebView)
    }

    func resolvedPageTitle(for webView: WKWebView? = nil) async -> String? {
        let webView = webView ?? wkWebView

        if let currentTitle = webView.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           !currentTitle.isEmpty {
            return currentTitle
        }

        if let jsTitle = try? await webView.evaluateJavaScript("document.title") as? String {
            let trimmedTitle = jsTitle.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedTitle.isEmpty ? nil : trimmedTitle
        }

        return nil
    }

    func recordHistory(
        url: URL,
        modelContext: ModelContext,
        existingItems: [HistoryEntry]
    ) {
        if let appError = PDFFileHistoryService.record(
            url: url,
            modelContext: modelContext,
            existingItems: existingItems
        ) {
            setError(appError)
        } else {
            clearError()
        }
    }

    func resetCommonState() {
        clearError()
        pdfFileDocument = nil
        urlString = ""
        status = ""
        isExporting = false
    }

    func clearLoadedPage() {
        wkWebView.loadHTMLString("", baseURL: nil)
        isClearingWebView = true
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

private func makeWebView(frame: CGRect = .zero) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    return WKWebView(frame: frame, configuration: configuration)
}
