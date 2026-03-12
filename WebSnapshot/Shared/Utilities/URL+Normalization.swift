//
//  URL+Normalization.swift
//  WebSnapshot
//
//  Created by fluciumt on 2026/03/11.
//

import Foundation

extension URL {
    var isSupportedWebURL: Bool {
        guard let scheme = scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        guard let host = host?.lowercased(), !host.isEmpty else {
            return false
        }

        return Self.isValidWebHost(host)
    }
    
    static func normalized(from string: String) -> URL? {
        normalizedWebURL(from: string)
    }

    static func normalizedWebURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }

        let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
            ? trimmed
            : "https://\(trimmed)"

        guard let url = URL(string: normalized), url.isSupportedWebURL else {
            return nil
        }

        return url
    }

    static func parseWebURLs(from multilineText: String) -> (urls: [URL], invalidLineNumbers: [Int]) {
        var urls: [URL] = []
        var invalidLineNumbers: [Int] = []

        for (index, rawLine) in multilineText.components(separatedBy: .newlines).enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }

            if let url = normalizedWebURL(from: trimmed) {
                urls.append(url)
            } else {
                invalidLineNumbers.append(index + 1)
            }
        }

        return (urls, invalidLineNumbers)
    }

   
}

private extension URL {
    static func isValidWebHost(_ host: String) -> Bool {
        if host == "localhost" || isIPv4(host) {
            return true
        }

        guard host.contains(".") else {
            return false
        }

        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }

        let allowedHostChars = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
        return labels.allSatisfy { label in
            !label.isEmpty && label.unicodeScalars.allSatisfy { allowedHostChars.contains($0) }
        }
    }

    static func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return false
        }

        for part in parts {
            guard let value = Int(part), String(value) == part, (0...255).contains(value) else {
                return false
            }
        }

        return true
    }
}
