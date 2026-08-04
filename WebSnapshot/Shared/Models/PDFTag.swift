import Foundation
import SwiftData

@Model
final class PDFTag {
    @Attribute(.unique) var normalizedName: String
    
    @Relationship(inverse: \PDFFile.tags) var pdfFiles: [PDFFile] = []

    var name: String
    
    init(_ name: String, normalizedName: String) {
        self.name = name
        self.normalizedName = normalizedName
    }
}
