import Foundation

extension URL {
    
    static func pdfFileName(
        _ title:String?,
        _ url: URL?
    ) -> String {
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleanTitle = trimmedTitle.components(separatedBy: invalidCharacters).joined()
        let source = cleanTitle.isEmpty ? (url?.removingScheme ?? "page") : cleanTitle
        let name = source.components(
            separatedBy: invalidCharacters
        ).joined()
        let baseName = name.lowercased().hasSuffix(".pdf") ? String(name.dropLast(4)) : name
        return (baseName.isEmpty ? "page" : baseName) + ".pdf"
    }
    
    
    private var removingScheme: String {
        guard let scheme = self.absoluteString.range(
            of: "://"
        ) else {
            return self.absoluteString
        }
        
        return String(
            self.absoluteString[scheme.upperBound...]
        )
    }
    
}
