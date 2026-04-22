import Foundation

extension URL{
  
    var isSupportedWebURL: Bool {
        Self.isSupportedWebURL(self)
    }
    
    var isLikelyPDFResource: Bool {
        return path.lowercased().hasSuffix(".pdf") || lastPathComponent.lowercased().contains(".pdf")
    }
    
    static func normalizedMultiple(_ string: String) -> (urls:[URL],invalidLineNumbers: [Int]){
        var urls: [URL] = []
           
        var invalidLineNumbers: [Int] = []
        
        for (i, line) in string.components(separatedBy: .newlines).enumerated() {
               
            let line = line.trimmingCharacters(in: .whitespacesAndNewlines)
               
            guard line.isEmpty == false else {
                continue
            }
               
            if let url = normalized(line){
                urls.append(url)
            } else {
                invalidLineNumbers.append(i + 1)
            }
        }
           
        return (urls, invalidLineNumbers)
    }
    
    static func normalized(_ string: String) -> URL? {
          let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

          guard trimmed.isEmpty == false else {
              return nil
          }

          let normalized = if trimmed == removingScheme(trimmed) {
              "https://\(trimmed)"
          } else {
              trimmed
          }

          guard let url = URL(string: normalized), isSupportedWebURL(url) else {
              return nil
          }

          return url
      }
}

private extension URL{
    private static func isSupportedWebURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }

        guard let host = url.host?.lowercased(), host.isEmpty == false else {
            return false
        }

        if localHost(host) || isIPv4(host) {
            return true
        }

        guard host.contains(".") else {
            return false
        }

        let entries = host.split(separator: ".",omittingEmptySubsequences: false)
          
        guard entries.count >= 2 else {
            return false
        }
          
        return entries.allSatisfy {entry in entry.isEmpty == false && entry.unicodeScalars.allSatisfy { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").contains($0) }}
    }
      
      
    private static func localHost(_ host: String) -> Bool {
        host == "localhost"
    }
    
    private static func isIPv4(_ host: String) -> Bool {
        var in_address = in_addr()
        
        return host.withCString { cString in inet_pton(AF_INET, cString, &in_address) == 1}
    }
}
