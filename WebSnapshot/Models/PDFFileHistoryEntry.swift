//
//  PDFFileHistoryEntry.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import Foundation
import SwiftData

@Model
final class PDFFileHistoryEntry {
    var url: URL

    init(url: URL) {
        self.url = url
    }
}

extension PDFFileHistoryEntry {
    
    var fileURL: URL {
        url
    }

    var fileName: String {
        fileURL.lastPathComponent
    }
}
