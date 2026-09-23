import Foundation

nonisolated struct SafariCaptureRequest: Equatable, Sendable {
    let id: UUID
    let url: URL

    enum InvalidRequest: Error, LocalizedError {
        case malformed

        var errorDescription: String? {
            "Open an HTTP or HTTPS webpage in Safari and try again."
        }
    }

    init(id: UUID,url: URL) throws {
        guard url.absoluteString.utf8.count <= 32_768, let scheme = url.scheme?.lowercased(), ["http","https"].contains(scheme), let host = url.host, !host.isEmpty, url.user == nil, url.password == nil else {
                throw InvalidRequest.malformed
            }
        
        self.id = id
        
        self.url = url
    }
    
    init(message: [String: Any]) throws {
        guard message["type"] as? String == "save-page", let id = message["id"] as? String, let uuid = UUID(uuidString: id), let address = message["url"] as? String, let url = URL(string: address) else {
            throw InvalidRequest.malformed
        }
        
        try self.init(id: uuid,url: url)
    }
    
    init(openURL: URL) throws {
        
        guard let components = URLComponents(url: openURL,resolvingAgainstBaseURL: false),
        components.scheme == "websnapshot", components.host == "capture",
        components.path.isEmpty, components.user == nil, components.password == nil,
        components.port == nil, components.fragment == nil,
       
        let items = components.queryItems, items.count == 2, items.filter({
            $0.name == "id"
        }).count == 1, items.filter({
            $0.name == "url"
        }).count == 1,
        let id = items.first(where: {
            $0.name == "id"
        })?.value,
        let uuid = UUID(uuidString: id),
        let address = items.first(where: {
            $0.name == "url"
        })?.value,
        let url = URL(string: address) else {
            throw InvalidRequest.malformed
        }
        
        try self.init(id: uuid,url: url)
    }
    
    var openURL: URL {
        var components = URLComponents()
        
        components.scheme = "websnapshot"
        
        components.host = "capture"
        
        components.queryItems = [
            URLQueryItem(name: "id",value: id.uuidString),
            URLQueryItem(name: "url",value: url.absoluteString),
        ]
        
        return components.url!
    }
}
    