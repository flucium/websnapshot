//
//  WebViewFactory.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/16.
//

import CoreGraphics
import WebKit

enum WebViewFactory {
    static func make(frame: CGRect = .zero) -> WKWebView {
        let configuration = WKWebViewConfiguration()
#if os(iOS)
        configuration.defaultWebpagePreferences.preferredContentMode = .desktop
#endif
        return WKWebView(frame: frame, configuration: configuration)
    }
}
