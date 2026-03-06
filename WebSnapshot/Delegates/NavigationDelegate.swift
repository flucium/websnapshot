//
//  NavigationDelegate.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import WebKit

final class NavigationDelegate: NSObject, WKNavigationDelegate {

    var onFinish: (() -> Void)?

    var onError: ((String) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }
}
