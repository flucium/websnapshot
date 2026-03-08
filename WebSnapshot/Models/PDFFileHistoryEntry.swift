//
//  PDFHistoryEntry.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/07.
//

import Foundation
import SwiftData

@Model
final class PDFFileHistoryEntry {
    var path: String

    init(path: String) {
        self.path = path
    }
}

extension PDFFileHistoryEntry {
    var fileURL: URL {
        URL(fileURLWithPath: path)
    }

    var fileName: String {
        fileURL.lastPathComponent
    }
}
