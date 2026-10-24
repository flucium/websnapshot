import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
func directoryPanel(_ directoryURL: URL?, _ title: String = "Choose Storage Folder", _ prompt: String = "Choose")
    -> URL?
{

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
func importPDFsPanel() -> [URL]? {
    let panel = NSOpenPanel()

    panel.allowedContentTypes = [.pdf]
    panel.canChooseFiles = true
    panel.canChooseDirectories = false
    panel.allowsMultipleSelection = true
    panel.title = "Import PDFs"
    panel.prompt = "Import"

    return panel.runModal() == .OK ? panel.urls : nil
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
func savePanel(_ fileName: String) -> URL? {
    let panel = NSSavePanel()
    
    panel.allowedContentTypes = [.pdf]
    
    panel.canCreateDirectories = true
    
    panel.title = "Save"
    
    panel.nameFieldStringValue = fileName
    
    panel.directoryURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    
    return panel.runModal() == .OK ? panel.url : nil
}
