//
//  URL+PDFFileName.swift
//  WebSnapshot
//
//  Created by flicumt on 2026/03/11.
//

import Foundation

extension URL {
    static func pdfBaseName(
        title: String?,
        fallbackURL: URL?,
        fallbackPrefix: String = "page"
    ) -> String {
        let cleanedTitle = sanitizeFileName(title ?? "")
        if !cleanedTitle.isEmpty {
            return cleanedTitle
        }

        if let fallbackURL {
            return filename(for: fallbackURL).replacingOccurrences(of: ".pdf", with: "")
        }

        return fallbackPrefix
    }

    static func pdfFileName(
        title: String?,
        fallbackURL: URL?,
        fallbackPrefix: String = "page"
    ) -> String {
        "\(pdfBaseName(title: title, fallbackURL: fallbackURL, fallbackPrefix: fallbackPrefix)).pdf"
    }

    static func filename(for url: URL) -> String {
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

    static func sanitizeFileName(_ rawValue: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        return rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalid)
            .joined()
    }
}
