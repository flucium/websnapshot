//
//  HistoryEntry.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import SwiftData

@Model
final class HistoryEntry {
    var url: URL

    init(url: URL) {
        self.url = url
    }
}

extension HistoryEntry {
    
    var fileURL: URL {
        url
    }

    var fileName: String {
        fileURL.lastPathComponent
    }
}
