//
//  HistoryService.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import Foundation
import PDFKit

func deletePDFFile(url: URL) throws {
    guard withSecurityScopedAccess(url: url, action: { FileManager.default.fileExists(atPath: url.path) }) else {
        throw CocoaError(.fileNoSuchFile)
    }

    guard isPDFFile(url: url) else {
        throw CocoaError(.fileReadCorruptFile)
    }

    do {
        try withSecurityScopedAccess(url: url) {
            try FileManager.default.removeItem(at: url)
        }
    } catch {
        throw CocoaError(.fileWriteNoPermission)
    }
}

func isPDFFile(url: URL) -> Bool {
    guard withSecurityScopedAccess(url: url, action: { FileManager.default.fileExists(atPath: url.path) }) else {
        return false
    }

    guard let document = withSecurityScopedAccess(url: url, action: { PDFDocument(url: url) }) else {
        return false
    }

    return document.pageCount > 0
}

private func withSecurityScopedAccess<T>(url: URL, action: () throws -> T) rethrows -> T {
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
