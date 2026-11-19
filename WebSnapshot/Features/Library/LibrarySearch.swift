import Foundation

enum LibrarySearch {
    static func matches(_ pdfFile: PDFFile, _ input: String, _ librarySerchMode: LibrarySearchMode, title: String? = nil) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    
        guard !text.isEmpty else {
            return true
        }
        
        let titleMatches = (title ?? pdfFile.resolvedURL.lastPathComponent).localizedCaseInsensitiveContains(text)
        
        let tagMatches = pdfFile.tags.contains {
            $0.name.localizedCaseInsensitiveContains(text)
        }
        
        switch librarySerchMode {
        case .all:
            return titleMatches || tagMatches || (pdfFile.searchableText?.localizedCaseInsensitiveContains(text) ?? false)
        case .title:
            return titleMatches
        case .tag:
            return tagMatches
        }
    }
}
