//
//  URL+Normalization.swift
//  WebSnapshot
//
//  Created by fluciumt on 2026/03/11.
//

import Foundation

extension URL {
    
    static func normalized(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = (trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://"))
        ? trimmed
        : "https://\(trimmed)"
        
        return URL(string: normalized)
    }
}
