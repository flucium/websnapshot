import Foundation

extension URL{
    static func supportedWebURL(
        _ input: String
    ) -> URL? {
        let trimmedInput = input.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        
        guard trimmedInput.isEmpty == false else {
            return nil
        }
        
        let candidate: String
        
        if trimmedInput
            .contains(
                "://"
            ) {
            candidate = trimmedInput
        } else {
            candidate = "https://" + trimmedInput
        }
        
        guard let url = URL(
            string: candidate
        ), url.isSupportedWebURL else {
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
        
        // true localhost or ipaddress(IPv4)
        if localHost(
            host
        ) || isIPv4(
            host
        ) {
            return true
        }
        
        // domain check
        guard host
            .contains(
                "."
            ) else {
            return false
        }
        
        let entries = host.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        
        guard entries.count >= 2 else {
            return false
        }
        
        return entries
            .allSatisfy {
                entry in entry.isEmpty == false && entry.unicodeScalars
                    .allSatisfy {
                        CharacterSet(
                            charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-"
                        )
                        .contains(
                            $0
                        )
                    }
            }
    }
    
}

extension URL {
    @inline(
        __always
    )
    private func localHost(
        _ host: String
    ) -> Bool {
        host == "localhost"
    }
    
    @inline(
        __always
    )
    private func isIPv4(
        _ host: String
    ) -> Bool {
        var in_address = in_addr()
        
        return host
            .withCString {
                cString in
                inet_pton(
                    AF_INET,
                    cString,
                    &in_address
                ) == 1
        }
    }
}
