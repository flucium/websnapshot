//
//  HomeViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import Foundation
import WebKit
import AppKit
import Combine

@MainActor
class WebViewModel: ObservableObject {

    @Published var status: String = ""

    func makePDF(webView: WKWebView) async throws -> Data {
        try await pdfData(from: webView)
    }

    func createPDFData(from webView: WKWebView) async throws -> Data {
        try await pdfData(from: webView)
    }

    func chooseDirectory(completion: @escaping (URL?) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.title = "Choose Save Folder"
        panel.message = "Select a folder to save the PDFs."
        panel.prompt = "Choose"

        panel.begin { response in
            if response == .OK {
                completion(panel.url)
            } else {
                completion(nil)
            }
        }
    }

    func filename(for url: URL, index: Int) -> String {
        let host = url.host ?? "page"
        let path = url.path
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        if path.isEmpty {
            return "\(host).pdf"
        } else {
            return "\(host)\(path).pdf"
        }
    }

    func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            ? trimmed
            : "https://\(trimmed)"

        return URL(string: normalized)
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
}
