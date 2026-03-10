//
//  WebItem.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import Foundation
import WebKit

final class WebItem: Identifiable {
    let id = UUID()
    let url: URL
    let webView: WKWebView

    init(url: URL) {
        self.url = url
        self.webView = WKWebView()
        self.webView.load(URLRequest(url: url))
    }
}
