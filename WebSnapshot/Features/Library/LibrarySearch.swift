import Foundation

enum LibrarySearch {
    
    static func matches(_ pdf: PDFFile, _ input: String, _ mode: LibrarySearchMode) -> Bool {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
    
        guard !text.isEmpty else {
            return true
        }
        
        let titleMatches = pdf.resolvedURL.lastPathComponent.localizedCaseInsensitiveContains(text)
        
        let tagMatches = pdf.tags.contains {
            $0.name.localizedCaseInsensitiveContains(text)
        }
        
        switch mode {
        case .all:
            return titleMatches || tagMatches || (pdf.searchableText?.localizedCaseInsensitiveContains(text) ?? false)
        case .title:
            return titleMatches
        case .tag:
            return tagMatches
        }
    }
}
