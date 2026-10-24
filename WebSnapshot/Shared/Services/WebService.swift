import WebKit

enum WebService{
    static func fetch(_ url:URL,_ onStart: (WebPage) -> Void = { _ in }) async throws -> WebPage{
        
        let websiteDataStore = WKWebsiteDataStore.nonPersistent()
        
        await websiteDataStore.httpCookieStore.setCookiePolicy(.disallow)
        
        var configuration = WebPage.Configuration()
        
        configuration.websiteDataStore = websiteDataStore
        
        let webPage:WebPage = WebPage(configuration: configuration)
        
        try Task.checkCancellation()
        
        let navigation = webPage.load(url)
        
        onStart(webPage)

        do {
            try await waitForNavigation(navigation)
        
            return webPage
        } catch {
            
            webPage.stopLoading()
            
            throw error
        }
    }

    static func waitForNavigation<Events: AsyncSequence>(_ events: Events) async throws where Events.Element == WebPage.NavigationEvent {
        do {
            for try await event in events {
                
                try Task.checkCancellation()
                
                if event == .finished {
                    return
                }
                
            }
            
            try Task.checkCancellation()
            
            throw AppError.invalidLoad("The webpage stopped loading before it finished.")
            
        } catch WebPage.NavigationError.failedProvisionalNavigation(let error) {
            
            throw AppError(error)
        }
    }
}
