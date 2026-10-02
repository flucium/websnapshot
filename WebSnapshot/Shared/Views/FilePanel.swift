import Foundation
import AppKit
import UniformTypeIdentifiers

@MainActor
func directoryPanel(_ directoryURL: URL?, _ title: String = "Choose Storage Folder", _ prompt: String = "Choose") -> URL? {
    
    let panel = NSOpenPanel()

    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.title = title
    panel.prompt = prompt
    panel.directoryURL = directoryURL

    guard panel.runModal() == .OK else {
        return nil
    }

    return panel.url
}

@MainActor
func importPDFPanel() -> URL? {
    let panel = NSOpenPanel()

    panel.allowedContentTypes = [.pdf]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = false
    panel.title = "Import PDF"
    panel.prompt = "Import"

    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func exportPDFPanel(_ fileName: String) -> URL? {
    let panel = NSSavePanel()

    panel.allowedContentTypes = [.pdf]
    panel.canCreateDirectories = true
    panel.title = "Export PDF"
    panel.prompt = "Export"
    panel.nameFieldStringValue = fileName

    if let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first {
        panel.directoryURL = documents
    }

    return panel.runModal() == .OK ? panel.url : nil
}

@MainActor
func savePanel(_ title: String,_ url: URL?,_ pdfFileDocument: PDFFileDocument?,beforeWrite: () throws -> Void = {}) throws -> URL? {
    guard let data = pdfFileDocument?.data else {
        return nil
    }
    
    let panel = NSSavePanel()
    
    panel.allowedContentTypes = [.pdf]
    panel.canCreateDirectories = true
    panel.title = "Save"
    panel.nameFieldStringValue = URL.pdfFileName(title,url)
    
    FileManager.default.urls(for: .documentDirectory,in: .userDomainMask).first.map {
        panel.directoryURL = $0
    }

    prepareForSafariDialog()
    
    guard panel.runModal() == .OK, let destination = panel.url else {
        return nil
    }
    
    do {
        try beforeWrite()
        
        try data.write(to: destination,options: .atomic)
        
        return destination
    } catch {
        throw AppError(error)
    }
}

@MainActor
func prepareForSafariDialog() {
    if NSApp.isHidden {
        for window in NSApp.windows where !(window is NSPanel) {
            window.orderOut(nil)
        }
        NSApp.unhide(nil)
    }
    NSApp.activate(ignoringOtherApps: true)
}

@MainActor
func saveToDirectory(_ title: String,_ url: URL?,_ pdfFileDocument: PDFFileDocument?,_ directoryURL: URL) throws -> URL? {
    
    guard let data = pdfFileDocument?.data else {
        return nil
    }

    let fileName = URL.pdfFileName(title,url)
    
    let destination = availablePDFURL(directoryURL,fileName)

    do {
        try data.write(to: destination,options: .atomic)
        
        return destination
    } catch {
        throw AppError(error)
    }
}

func availablePDFURL(_ directoryURL: URL,_ fileName: String) -> URL {
    
    var candidate = directoryURL.appendingPathComponent(fileName)
    
    var suffix = 2

    while FileManager.default.fileExists(atPath: candidate.path) {
        candidate = directoryURL.appendingPathComponent(URL.pdfFileName(fileName, nil,  " \(suffix)"))
        suffix += 1
    }

    return candidate
}
