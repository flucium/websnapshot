//
//  URL+PDFFileName.swift
//  WebSnapshot
//
//  Created by flicumt on 2026/03/11.
//

import Foundation

extension URL{ 
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
}
