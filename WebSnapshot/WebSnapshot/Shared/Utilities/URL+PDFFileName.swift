import Foundation

extension URL {
    static func makePDFFileName(title: String?,fallbackURL: URL?,fallbackPrefix: String = "page") -> String {
        "\(makePDFBaseName( title,  fallbackURL,  fallbackPrefix)).pdf"
    }
      
    
    static func makePDFFileName(_ url: URL) -> String {
        let baseName = removingScheme(url.absoluteString).trimmingCharacters(in: CharacterSet(charactersIn: "/"))

        return baseName.isEmpty ? "page.pdf" : "\(baseName).pdf"
    }
    
}

private extension URL {
    private static func makePDFBaseName(_ title: String?, _ fallbackURL: URL?, _ fallbackPrefix: String = "page") -> String {
        
        let sanitized = sanitizedFileNameComponent(title ?? "")
        
        if sanitized.isEmpty == false{
            return sanitized
        }

        if let fallbackURL {
              return makePDFFileName(fallbackURL).replacingOccurrences(of: ".pdf", with: "")
        }

        return fallbackPrefix
    }
    
    private static func sanitizedFileNameComponent(_ string: String) -> String {
        return string.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
    }
}
