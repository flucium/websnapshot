import WebKit

@MainActor
struct WebExportSource {
    private let url: URL
    private let token = UUID().uuidString

    init(_ page: WebPage) async throws {

        guard let url = page.url, url.isSupportedWebURL, !page.isLoading else {
            throw AppError.invalidLoad("Wait for the webpage to finish loading before saving.")
        }

        self.url = url
        
        _ = try await page.callJavaScript("document.__webSnapshotExportToken = token; return true;", arguments: ["token": token], contentWorld: .defaultClient)
        
        try await validate(page)
    }

    func validate(_ page: WebPage) async throws {
        
        try Task.checkCancellation()
        
        guard page.url == url, !page.isLoading else {
            throw navigationError
        }
        
        let address = try await page.callJavaScript("return document.__webSnapshotExportToken === token ? location.href : null;", arguments: ["token": token], contentWorld: .defaultClient) as? String
        
        try Task.checkCancellation()
        
        guard let address, URL(string: address) == url, page.url == url, !page.isLoading else {
            throw navigationError
        }
    }

    private var navigationError: AppError {
        .invalidLoad("The webpage changed while saving. Wait for it to finish loading and save again.")
    }
}
