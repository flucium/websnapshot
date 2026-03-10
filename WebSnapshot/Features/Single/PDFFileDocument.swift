//
//  Untitled.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//


import SwiftUI
import UniformTypeIdentifiers

struct PDFFileDocument: FileDocument {
    
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
