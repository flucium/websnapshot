//
//  WebPageLoader.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/16.
//

import Foundation
import WebKit

enum WebPageLoader {
    static func load(_ url: URL, into webView: WKWebView) {
        let request = URLRequest(url: url)

#if os(iOS)
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                guard shouldLoadHTMLData(from: response) else {
                    await MainActor.run {
                        webView.load(request)
                    }
                    return
                }

                let encodingName = response.textEncodingName
                    ?? detectedEncodingName(in: data)
                    ?? "utf-8"

                await MainActor.run {
                    webView.load(
                        data,
                        mimeType: response.mimeType ?? "text/html",
                        characterEncodingName: encodingName,
                        baseURL: response.url ?? url
                    )
                }
            } catch {
                await MainActor.run {
                    webView.load(request)
                }
            }
        }
#else
        webView.load(request)
#endif
    }

    private static func shouldLoadHTMLData(from response: URLResponse) -> Bool {
        guard let mimeType = response.mimeType?.lowercased() else {
            return false
        }

        return mimeType.hasPrefix("text/html") || mimeType == "application/xhtml+xml"
    }

    private static func detectedEncodingName(in data: Data) -> String? {
        let head = String(decoding: data.prefix(4096), as: UTF8.self).lowercased()

        let patterns = [
            #"charset\s*=\s*["']?\s*([a-z0-9._-]+)"#,
            #"<meta[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([a-z0-9._-]+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
                continue
            }

            let range = NSRange(head.startIndex..<head.endIndex, in: head)
            guard let match = regex.firstMatch(in: head, options: [], range: range),
                  match.numberOfRanges > 1,
                  let encodingRange = Range(match.range(at: 1), in: head) else {
                continue
            }

            return String(head[encodingRange])
        }

        return nil
    }
}
