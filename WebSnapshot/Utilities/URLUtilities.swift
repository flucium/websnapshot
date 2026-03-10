//
//  URLService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import Foundation

class URLUtilities{
    
    func makePDFFileName(for url: URL) -> String {
        let host = url.host ?? "page"
        
        let path = url.path
        
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))
        
        if path.isEmpty {
            return "\(host).pdf"
        } else {
            return "\(host)\(path).pdf"
        }
    }
    
    func normalizedURL(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        
        let normalized = (
            trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
        )
        ? trimmed
        : "https://\(trimmed)"

        guard
            let url = URL(string: normalized),
            let scheme = url.scheme?.lowercased(),
            (scheme == "http" || scheme == "https"),
            let host = url.host,
            !host.isEmpty
        else {
            return nil
        }

        return url
    }
}
