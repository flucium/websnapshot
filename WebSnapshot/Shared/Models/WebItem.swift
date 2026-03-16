//
//  WebItem.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import CoreGraphics
import WebKit

final class WebItem: Identifiable {
    let id = UUID()
    let url: URL
    let webView: WKWebView

    init(url: URL) {
        self.url = url
        let configuration = WKWebViewConfiguration()
        self.webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView.load(URLRequest(url: url))
    }
}
