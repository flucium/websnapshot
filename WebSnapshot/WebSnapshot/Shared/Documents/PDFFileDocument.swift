import SwiftUI
import UniformTypeIdentifiers

final class PDFFileDocument: FileDocument {
    
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(_ data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
