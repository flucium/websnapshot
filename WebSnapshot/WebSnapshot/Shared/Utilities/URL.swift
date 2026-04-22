import Foundation


extension URL {
    static func removingScheme(_ string: String) -> String {
        guard let scheme = string.range(of: "://") else {
            return string
        }

        return String(string[scheme.upperBound...])
    }
    
}
