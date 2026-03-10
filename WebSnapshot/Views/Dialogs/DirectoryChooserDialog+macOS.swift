//
//  DirectoryChooserDialog.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

#if os(macOS)

import AppKit

extension DirectoryChooserDialog {

    static func choose() -> URL? {
        let panel = NSOpenPanel()

        panel.canChooseFiles = false
        
        panel.canChooseDirectories = true
        
        panel.allowsMultipleSelection = false
        
        panel.canCreateDirectories = true

        panel.title = "Select a folder"
        
        panel.message = "Select a folder to save the PDFs."
        
        panel.prompt = "Save"

        return panel.runModal() == .OK ? panel.url : nil
    }
}

#endif
