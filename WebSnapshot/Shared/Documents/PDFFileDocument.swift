import SwiftUI
import UniformTypeIdentifiers

final class PDFFileDocument: FileDocument {
    
    static var readableContentTypes: [UTType] { [.pdf] }

    var data: Data

    init(_ data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        self.data = try Self.validatedData(configuration.file.regularFileContents)
    }

    static func validatedData(_ data: Data?) throws -> Data {
        guard let data, data.isEmpty == false else {
            throw AppError.invalidFileType("The selected file does not contain PDF data.")
        }

        return data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
