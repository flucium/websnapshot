//
//  PDFService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import WebKit

final class PDFService {

    func pdfData(from webView: WKWebView) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            let config = WKPDFConfiguration()

            webView.createPDF(configuration: config) { result in
                continuation.resume(with: result)
            }
        }
    }

}
