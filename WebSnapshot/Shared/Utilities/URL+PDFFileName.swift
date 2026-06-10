import Foundation

extension URL {
    
    static func pdfFileName(_ title:String?, _ url: URL?) -> String {
        if title != nil{
            let string = title!.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
            
            if string.isEmpty == false{
                return string
            }
        }
        
        
        let string = url?.removingScheme ?? "page"
        
        let fileName = string + ".pdf"
        
        return fileName
    }
    
    
    private var removingScheme: String {
        guard let scheme = self.absoluteString.range(of: "://") else {
            return self.absoluteString
        }

        return String(self.absoluteString[scheme.upperBound...])
    }
    
}
