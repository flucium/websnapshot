//
//  MultipleViewModel.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import Foundation
import Combine
import WebKit

@MainActor
final class MultipleState: WebState {
    @Published private(set) var items: [WebItem] = []
    @Published var isSelectingSaveFolder = false

    var onFileSaved: ((URL) -> Void)?

    var validLinkCount: Int {
        items.count
    }
    
    var canTapSaveButton: Bool {
        hasEditorInput && !hasInvalidLinks
    }
    
    var errorMessage: String? {
        appError?.errorDescription
    }

    override func load() {
        guard let urls = validatedURLs() else {
            return
        }
        items = urls.map { WebItem(url: $0) }
        status = "Loaded \(items.count) links"
    }

    override func clear() {
        urlString = ""
        items = []
        isSelectingSaveFolder = false
        clearError()
        status = ""
    }

    func preparePDFExport() {
        guard validatedURLs() != nil else {
            return
        }
        
        guard !items.isEmpty else {
            setError(.display(message: "No loaded pages to save. Press Load first."))
            return
        }

        clearError()
        status = "Choose a destination folder..."
        isSelectingSaveFolder = true
    }

    func setOnFileSaved(_ handler: @escaping (URL) -> Void) {
        onFileSaved = handler
    }

    func saveAllPDFs(to folderURL: URL) async {
        guard !items.isEmpty else {
            setError(.display(message: "No pages to save"))
            return
        }

        let didStartAccessing = folderURL.startAccessingSecurityScopedResource()
        guard didStartAccessing else {
            setError(.display(message: "Cannot access selected folder"))
            return
        }

        clearError()
        status = "Saving \(items.count) PDFs..."

        do {
            var savedCount = 0

            for (index, item) in items.enumerated() {
                guard !item.webView.isLoading else {
                    throw AppError.display(message: "Some pages are still loading. Try again in a moment.")
                }

                let data = try await makePDF(webView: item.webView)
                let defaultName = suggestedPDFFileName(for: item, index: index + 1)
                let destinationURL = uniqueDestinationURL(
                    in: folderURL,
                    defaultFileName: defaultName
                )

                try data.write(to: destinationURL, options: .atomic)
                onFileSaved?(destinationURL)

                savedCount += 1
                status = "Saved \(savedCount)/\(items.count)"
                if index == items.count - 1 {
                    status = "Saved \(savedCount) PDFs"
                }
            }
        } catch {
            setError(.display(message: "Failed to save PDFs: \(error.localizedDescription)"))
        }
    }

    private var hasEditorInput: Bool {
        !urlString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    private var hasInvalidLinks: Bool {
        !parseURLsWithInvalidLines(from: urlString).invalidLines.isEmpty
    }
    
    private func validatedURLs() -> [URL]? {
        guard hasEditorInput else {
            setError(.display(message: "Enter at least one link."))
            return nil
        }
        
        let parsed = parseURLsWithInvalidLines(from: urlString)
        guard parsed.invalidLines.isEmpty else {
            let invalidText = parsed.invalidLines.prefix(3).joined(separator: ", ")
            let suffix = parsed.invalidLines.count > 3 ? "..." : ""
            setError(.display(message: "Invalid link: \(invalidText)\(suffix)"))
            return nil
        }
        
        guard !parsed.urls.isEmpty else {
            setError(.display(message: "Enter at least one valid link."))
            return nil
        }
        
        clearError()
        return parsed.urls
    }
    
    private func parseURLsWithInvalidLines(from text: String) -> (urls: [URL], invalidLines: [String]) {
        var urls: [URL] = []
        var invalidLines: [String] = []
        
        let lines = text.components(separatedBy: .newlines)
        for (index, rawLine) in lines.enumerated() {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                continue
            }
            
            if let url = URL.normalized(from: trimmed), isValidWebURL(url) {
                urls.append(url)
            } else {
                invalidLines.append("line \(index + 1)")
            }
        }
        
        return (urls, invalidLines)
    }
    
    private func isValidWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        
        guard let host = url.host?.lowercased(), !host.isEmpty else {
            return false
        }
        
        return isValidHost(host)
    }
    
    private func isValidHost(_ host: String) -> Bool {
        if host == "localhost" {
            return true
        }
        
        if isIPv4(host) {
            return true
        }
        
        guard host.contains(".") else {
            return false
        }
        
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.count >= 2 else {
            return false
        }
        
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }
    }
    
    private func isIPv4(_ host: String) -> Bool {
        let parts = host.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else {
            return false
        }
        
        for part in parts {
            guard let value = Int(part), String(value) == part, (0...255).contains(value) else {
                return false
            }
        }
        
        return true
    }

    private func uniqueDestinationURL(in folderURL: URL, defaultFileName: String) -> URL {
        let fileManager = FileManager.default
        let ext = (defaultFileName as NSString).pathExtension
        let baseName = (defaultFileName as NSString).deletingPathExtension
        var candidate = folderURL.appendingPathComponent(defaultFileName)
        var counter = 2

        while fileManager.fileExists(atPath: candidate.path) {
            let nextName = ext.isEmpty ? "\(baseName)-\(counter)" : "\(baseName)-\(counter).\(ext)"
            candidate = folderURL.appendingPathComponent(nextName)
            counter += 1
        }

        return candidate
    }
    
    private func suggestedPDFFileName(for item: WebItem, index: Int) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let title = (item.webView.title ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: invalid)
            .joined()
        
        let baseName: String
        if !title.isEmpty {
            baseName = title
        } else {
            baseName = URL.filename(for: item.url).replacingOccurrences(of: ".pdf", with: "")
        }
        
        let normalizedBaseName = baseName.isEmpty ? "page-\(index)" : baseName
        return "\(normalizedBaseName).pdf"
    }
}
