import Foundation

extension URL {
    
    static func pdfFileName(_ title:String?,_ url: URL?,_ suffix: String = "") -> String {
        
        let trimmedTitle = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        let invalidCharacters = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        
        let cleanTitle = trimmedTitle.components(separatedBy: invalidCharacters).joined()
        
        let source = cleanTitle.isEmpty ? (url?.removingScheme ?? "page") : cleanTitle
        
        let name = source.components(separatedBy: invalidCharacters).joined()
        
        let baseName = name.lowercased().hasSuffix(".pdf") ? String(name.dropLast(4)) : name
        
        let byteLimit = 240 - suffix.utf8.count - ".pdf".utf8.count
        
        var shortenedName = ""
        
        var byteCount = 0
        
        for character in baseName {
        
            let size = String(character).utf8.count
            
            guard byteCount + size <= byteLimit else {
                break
            }
            
            shortenedName.append(character)
            
            byteCount += size
        }
        
        return (shortenedName.isEmpty ? "page" : shortenedName) + suffix + ".pdf"
    }
    
    
    private var removingScheme: String {
        guard let scheme = self.absoluteString.range(of: "://") else {
            return self.absoluteString
        }
        
        return String(self.absoluteString[scheme.upperBound...])
    }
    
}
