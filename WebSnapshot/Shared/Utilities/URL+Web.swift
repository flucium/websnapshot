import Foundation
import Darwin

extension URL{
    static func supportedWebURL(_ input: String) -> URL? {
        
        let trimmedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard trimmedInput.isEmpty == false else {
            return nil
        }
        
        let candidate: String
        
        if trimmedInput.contains("://") {
            candidate = trimmedInput
        } else {
            candidate = "https://" + trimmedInput
        }
        
        guard let url = URL(string: candidate), url.isSupportedWebURL else {
            return nil
        }
        
        return url
    }
    
    var isSupportedWebURL: Bool {
        
        // not http:// or https://
        guard let scheme = self.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
            return false
        }
        
        // not host
        guard let host = self.host?.lowercased(), host.isEmpty == false else {
            return false
        }
        
        // Accept IP literals before applying DNS label validation.
        let literal = URLComponents(url: self, resolvingAgainstBaseURL: false)?.host ?? host

        if literal.hasPrefix("[") || literal.hasSuffix("]") {
            return isIPv6(literal.lowercased())
        }

        if localHost(host) || isIPv4(host) {
            return true
        }
        
        // domain check
        let hostname = host.hasSuffix(".") ? String(host.dropLast()) : host

        let entries = hostname.split(separator: ".",omittingEmptySubsequences: false)
        
        guard entries.isEmpty == false else {
            return false
        }
        
        return entries.allSatisfy {
            entry in entry.isEmpty == false && !entry.hasPrefix("-") && !entry.hasSuffix("-") && entry.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-").contains($0)
            }
        }
    }
    
}

extension URL {
    @inline(__always)
    private func localHost(_ host: String) -> Bool {
        host == "localhost"
    }
    
    @inline(__always)
    private func isIPv4(_ host: String) -> Bool {
        
        var in_address = in_addr()
        
        return host.withCString {
            cString in
            inet_pton(AF_INET,cString,&in_address) == 1
        }
    }

    private func isIPv6(_ host: String) -> Bool {
        
        let literal = host.hasPrefix("[") && host.hasSuffix("]") ? String(host.dropFirst().dropLast()) : host
        
        let parts = literal.split(separator: "%", omittingEmptySubsequences: false)
        
        guard parts.count <= 2, parts.allSatisfy({
            !$0.isEmpty
        }) else {
            return false
        }
        
        var value = in6_addr()
        
        return String(parts[0]).withCString {
            inet_pton(AF_INET6, $0, &value) == 1
        }
    }
}
