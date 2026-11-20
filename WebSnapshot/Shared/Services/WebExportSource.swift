import WebKit

@MainActor
struct WebExportSource {
    private let url: URL
    
    private let token = UUID().uuidString

    init(_ webPage: WebPage) async throws {

        guard let url = webPage.url, url.isSupportedWebURL, !webPage.isLoading else {
            throw AppError.invalidLoad("Wait for the webpage to finish loading before saving.")
        }

        self.url = Self.documentURL(url)
        
        _ = try await webPage.callJavaScript("document.__webSnapshotExportToken = token; return true;", arguments: ["token": token], contentWorld: .defaultClient)
        
        try await validate(webPage)
    }

    func validate(_ webPage: WebPage) async throws {
        
        try Task.checkCancellation()
        
        guard webPage.url.map(Self.documentURL) == url, !webPage.isLoading else {
            throw navigationError
        }
        
        let address = try await webPage.callJavaScript("return document.__webSnapshotExportToken === token ? location.href : null;", arguments: ["token": token], contentWorld: .defaultClient) as? String
        
        try Task.checkCancellation()
        
        guard let address, let addressURL = URL(string: address), Self.documentURL(addressURL) == url,
              webPage.url.map(Self.documentURL) == url, !webPage.isLoading else {
            throw navigationError
        }
    }

    private static func documentURL(_ url: URL) -> URL {
        var components = URLComponents(url: url, resolvingAgainstBaseURL: true)
        
        components?.fragment = nil
        
        return components?.url ?? url
    }

    private var navigationError: AppError {
        .invalidLoad("The webpage changed while saving. Wait for it to finish loading and save again.")
    }
}
