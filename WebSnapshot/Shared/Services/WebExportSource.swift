import WebKit

@MainActor
struct WebExportSource {
    private let url: URL
    private let token = UUID().uuidString

    init(_ webPage: WebPage) async throws {

        guard let url = webPage.url, url.isSupportedWebURL, !webPage.isLoading else {
            throw AppError.invalidLoad("Wait for the webpage to finish loading before saving.")
        }

        self.url = url
        
        _ = try await webPage.callJavaScript("document.__webSnapshotExportToken = token; return true;", arguments: ["token": token], contentWorld: .defaultClient)
        
        try await validate(webPage)
    }

    func validate(_ webPage: WebPage) async throws {
        
        try Task.checkCancellation()
        
        guard webPage.url == url, !webPage.isLoading else {
            throw navigationError
        }
        
        let address = try await webPage.callJavaScript("return document.__webSnapshotExportToken === token ? location.href : null;", arguments: ["token": token], contentWorld: .defaultClient) as? String
        
        try Task.checkCancellation()
        
        guard let address, URL(string: address) == url, webPage.url == url, !webPage.isLoading else {
            throw navigationError
        }
    }

    private var navigationError: AppError {
        .invalidLoad("The webpage changed while saving. Wait for it to finish loading and save again.")
    }
}
