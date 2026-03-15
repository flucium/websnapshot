//
//  NavigationDelegate.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import WebKit

final class NavigationDelegate: NSObject, WKNavigationDelegate {

    var onFinish: (() -> Void)?

    var onError: ((String) -> Void)?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        logPageEncodingDetails(for: webView)
        onFinish?()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        onError?(error.localizedDescription)
    }

    private func logPageEncodingDetails(for webView: WKWebView) {
#if DEBUG
        let script = """
        (() => {
          const metaCharset = document.querySelector('meta[charset]')?.getAttribute('charset') ?? '';
          const metaContentType = document.querySelector('meta[http-equiv=\"content-type\" i]')?.getAttribute('content') ?? '';
          const title = document.title ?? '';
          const characterSet = document.characterSet ?? '';
          return JSON.stringify({
            title,
            characterSet,
            metaCharset,
            metaContentType
          });
        })();
        """

        let nativeTitle = webView.title ?? ""
        let url = webView.url?.absoluteString ?? "(no url)"

        print("[WebSnapshot] didFinish url=\(url)")
        print("[WebSnapshot] native title=\(nativeTitle)")

        webView.evaluateJavaScript(script) { result, error in
            if let error {
                print("[WebSnapshot] js inspect error=\(error.localizedDescription)")
                return
            }

            guard let payload = result as? String else {
                print("[WebSnapshot] js inspect returned non-string result")
                return
            }

            print("[WebSnapshot] js inspect=\(payload)")
        }
#endif
    }
}
