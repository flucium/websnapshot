//
//  HistoryService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import PDFKit

func deletePDFFile(url: URL) throws {
    try HistoryFileService.deletePDF(at: url)
}

func isPDFFile(url: URL) -> Bool {
    HistoryFileService.isPDF(at: url)
}

private enum HistoryFileService {
    static func deletePDF(at url: URL) throws {
        guard fileExists(at: url) else {
            throw CocoaError(.fileNoSuchFile)
        }

        guard isPDF(at: url) else {
            throw CocoaError(.fileReadCorruptFile)
        }

        do {
            try access(url) {
                try FileManager.default.removeItem(at: url)
            }
        } catch {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    static func isPDF(at url: URL) -> Bool {
        guard fileExists(at: url) else {
            return false
        }

        guard let document = pdfDocument(at: url) else {
            return false
        }

        return document.pageCount > 0
    }

    private static func fileExists(at url: URL) -> Bool {
        access(url) {
            FileManager.default.fileExists(atPath: url.path)
        }
    }

    private static func pdfDocument(at url: URL) -> PDFDocument? {
        access(url) {
            PDFDocument(url: url)
        }
    }
}

private func access<T>(_ url: URL, action: () throws -> T) rethrows -> T {
#if os(macOS)
    let didAccess = url.startAccessingSecurityScopedResource()
    defer {
        if didAccess {
            url.stopAccessingSecurityScopedResource()
        }
    }
#endif
    return try action()
}
