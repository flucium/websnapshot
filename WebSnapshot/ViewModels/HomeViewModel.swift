//
//  HomeViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//
import Foundation
import WebKit
import Combine


@MainActor
final class HomeViewModel: ObservableObject {

    @Published var urlString: String = "https://example.com"
    
    @Published var status: String = ""

    @Published var exportData: Data? = nil
    
    @Published var isExporting: Bool = false
    
    @Published var exportDocument: PDFFileDocument?
    
    let webPage = WKWebView(frame: .zero)

    private let navigationDelegate = NavigationDelegate()

      init() {

          webPage.navigationDelegate = navigationDelegate

          navigationDelegate.onFinish = { [weak self] in
              self?.status = ""
          }

          navigationDelegate.onError = { [weak self] message in
              self?.status = "Load failed: \(message)"
          }
      }
    
    func load() {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
          let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
              ? trimmed
              : "https://\(trimmed)"

          guard let url = URL(string: normalized) else {
              status = "Invalid URL"
              return
          }

          status = "Loading..."

          webPage.load(URLRequest(url: url))
    }
    
    func clear() {
        urlString = ""
        status = ""
        webPage.loadHTMLString("", baseURL: nil)
    }
    
    func makePDFForExport() {

        status = "Rendering PDF..."

        let config = WKPDFConfiguration()

        webPage.createPDF(configuration: config) { [weak self] result in
            guard let self else { return }

            switch result {

            case .success(let data):

                DispatchQueue.main.async {

                    self.exportData = data
                    self.isExporting = true
                    self.status = "Ready to export"

                }

            case .failure(let error):

                DispatchQueue.main.async {
                    self.status = "PDF failed: \(error.localizedDescription)"
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
