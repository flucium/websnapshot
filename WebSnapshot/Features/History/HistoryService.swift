//
//  HistoryService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import PDFKit

func deletePDFFile(url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
        throw CocoaError(.fileNoSuchFile)
    }

    guard isPDFFile(url: url) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    do {
        try FileManager.default.removeItem(at: url)
    } catch {
        throw CocoaError(.fileWriteNoPermission)
    }
}

func isPDFFile(url: URL) -> Bool {
    guard FileManager.default.fileExists(atPath: url.path) else {
        return false
    }

    guard let document = PDFDocument(url: url) else {
        return false
    }

    return document.pageCount > 0
}
