//
//  WebView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI
import CoreGraphics
import WebKit

struct WebViewContainer: View {
    let status: String
    var font: Font = .body

    var body: some View {
        Text(status)
            .font(font)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal)
    }
}

struct WebPreview: View {
    let webView: WKWebView
    var height: CGFloat? = nil
    var cornerRadius: CGFloat = 0

    var body: some View {
        WebView(webView: webView)
            .frame(maxWidth: .infinity, maxHeight: height == nil ? .infinity : nil)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}

#if os(macOS)

struct WebView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
#else

struct WebView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
#endif
