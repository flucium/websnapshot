import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
func directoryPanel(
    _ directoryURL: URL?
) -> URL? {
    let panel = NSOpenPanel()

    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.title = "Choose Storage Folder"
    panel.prompt = "Choose"
    panel.directoryURL = directoryURL

    guard panel.runModal() == .OK else {
        return nil
    }

    return panel.url
}

@MainActor
func savePanel(
    _ title: String,
    _ url: URL?,
    _ pdfFileDocument: PDFFileDocument?
) throws -> URL? {
    guard let data = pdfFileDocument?.data else {
        return nil
    }
    
    let panel = NSSavePanel()
    
    panel.allowedContentTypes = [.pdf]
    panel.canCreateDirectories = true
    panel.title = "Save"
    panel.nameFieldStringValue = URL
        .pdfFileName(
            title,
            url
        )
    
    FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first.map {
        panel.directoryURL = $0
    }
    
    guard panel
        .runModal() == .OK, let destination = panel.url else {
        return nil
    }
    
    do {
        try data
            .write(
                to: destination,
                options: .atomic
            )
        return destination
    } catch {
        throw AppError(
            error
        )
    }
}

@MainActor
func saveToDirectory(
    _ title: String,
    _ url: URL?,
    _ pdfFileDocument: PDFFileDocument?,
    _ directoryURL: URL
) throws -> URL? {
    guard let data = pdfFileDocument?.data else {
        return nil
    }

    let fileName = URL.pdfFileName(
        title,
        url
    )
    let destination = availablePDFURL(
        directoryURL,
        fileName
    )

    do {
        try data.write(
            to: destination,
            options: .atomic
        )
        return destination
    } catch {
        throw AppError(
            error
        )
    }
}

private func availablePDFURL(
    _ directoryURL: URL,
    _ fileName: String
) -> URL {
    let fileURL = URL(fileURLWithPath: fileName)
    let baseName = fileURL.deletingPathExtension().lastPathComponent
    let fileExtension = fileURL.pathExtension.isEmpty
        ? "pdf"
        : fileURL.pathExtension

    var candidate = directoryURL
        .appendingPathComponent(baseName)
        .appendingPathExtension(fileExtension)
    var suffix = 2

    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = directoryURL
            .appendingPathComponent("\(baseName) \(suffix)")
            .appendingPathExtension(fileExtension)
        suffix += 1
    }

    return candidate
}
