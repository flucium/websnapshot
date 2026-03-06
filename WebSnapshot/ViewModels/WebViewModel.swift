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



//import Foundation
//import WebKit
//import Combine
//
//
//@MainActor
//final class HomeViewModel: ObservableObject {
//
//    @Published var urlString: String = "https://example.com"
//    
//    @Published var status: String = ""
//
//    @Published var exportData: Data? = nil
//    
//    @Published var isExporting: Bool = false
//    
//    @Published var exportDocument: PDFFileDocument?
//    
//    let webPage = WKWebView(frame: .zero)
//
//    private let navigationDelegate = NavigationDelegate()
//
//      init() {
//
//          webPage.navigationDelegate = navigationDelegate
//
//          navigationDelegate.onFinish = { [weak self] in
//              self?.status = ""
//          }
//
//          navigationDelegate.onError = { [weak self] message in
//              self?.status = "Load failed: \(message)"
//          }
//      }
//    
//    func load() {
//        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
//          let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
//              ? trimmed
//              : "https://\(trimmed)"
//
//          guard let url = URL(string: normalized) else {
//              status = "Invalid URL"
//              return
//          }
//
//          status = "Loading..."
//
//          webPage.load(URLRequest(url: url))
//    }
//    
//    func clear() {
//        urlString = ""
//        status = ""
//        webPage.loadHTMLString("", baseURL: nil)
//    }
//    
//    func makePDF(webView: WKWebView) async throws -> Data {
//        try await withCheckedThrowingContinuation { continuation in
//
//            let config = WKPDFConfiguration()
//
//            webView.createPDF(configuration: config) { result in
//                switch result {
//
//                case .success(let data):
//                    continuation.resume(returning: data)
//
//                case .failure(let error):
//                    continuation.resume(throwing: error)
//                }
//            }
//        }
//    }
//
//    func chooseDirectory(completion: @escaping (URL?) -> Void) {
//           let panel = NSOpenPanel()
//           panel.canChooseFiles = false
//           panel.canChooseDirectories = true
//           panel.allowsMultipleSelection = false
//           panel.canCreateDirectories = true
//           panel.title = "Choose Save Folder"
//           panel.message = "Select a folder to save the PDFs."
//           panel.prompt = "Choose"
//
//           panel.begin { response in
//               if response == .OK {
//                   completion(panel.url)
//               } else {
//                   completion(nil)
//               }
//           }
//       }
//    
//    func createPDFData(from webView: WKWebView) async throws -> Data {
//            try await withCheckedThrowingContinuation { continuation in
//                let config = WKPDFConfiguration()
//
//                webView.createPDF(configuration: config) { result in
//                    switch result {
//                    case .success(let data):
//                        continuation.resume(returning: data)
//
//                    case .failure(let error):
//                        continuation.resume(throwing: error)
//                    }
//                }
//            }
//        }
//
//    
//
//    func filename(for url: URL, index: Int) -> String {
//        let host = url.host ?? "page"
//        let path = url.path
//            .replacingOccurrences(of: "/", with: "_")
//            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
//
//        if path.isEmpty {
//            return "\(host).pdf"
//        } else {
//            return "\(host)\(path).pdf"
//        }
//    }
//    
//    
//    func makePDFsForExport(items: [WebItem]) {
//        guard !items.isEmpty else {
//            status = "No pages to save"
//            return
//        }
//
//        status = "Rendering PDFs..."
//
//        chooseDirectory { [weak self] folderURL in
//            guard let self else { return }
//
//            guard let folderURL else {
//                DispatchQueue.main.async {
//                    self.status = "Export cancelled"
//                }
//                return
//            }
//
//            Task {
//                do {
//                    for (index, item) in items.enumerated() {
//                        let data = try await self.createPDFData(from: item.webView)
//                        let fileURL = folderURL.appendingPathComponent(
//                            self.filename(for: item.url, index: index)
//                        )
//
//                        try data.write(to: fileURL)
//
//                        await MainActor.run {
//                            self.status = "Saved \(index + 1)/\(items.count)"
//                        }
//                    }
//
//                    await MainActor.run {
//                        self.status = "All PDFs saved"
//                    }
//
//                } catch {
//                    await MainActor.run {
//                        self.status = "PDF export failed: \(error.localizedDescription)"
//                    }
//                }
//            }
//        }
//    }
//    
//    func makePDFForExport() {
//
//        status = "Rendering PDF..."
//
//        let config = WKPDFConfiguration()
//
//        webPage.createPDF(configuration: config) { [weak self] result in
//            guard let self else { return }
//
//            switch result {
//
//            case .success(let data):
//
//                DispatchQueue.main.async {
//
//                    self.exportData = data
//                    self.isExporting = true
//                    self.status = "Ready to export"
//
//                }
//
//            case .failure(let error):
//
//                DispatchQueue.main.async {
//                    self.status = "PDF failed: \(error.localizedDescription)"
//                }
//            }
//        }
//    }
//
//    func suggestedFileName() -> String {
//        let rawTitle = webPage.title ?? "page"
//        
//        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
//        
//        let cleaned = rawTitle.components(separatedBy: invalid).joined()
//        
//        return cleaned.isEmpty ? "page" : cleaned
//    }
//}
