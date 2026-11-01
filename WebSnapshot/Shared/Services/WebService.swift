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

    static func waitForNavigation<Events: AsyncSequence>(_ events: Events, timeout: Duration = .seconds(30)) async throws where Events.Element == WebPage.NavigationEvent {
        try Task.checkCancellation()

        let completion = AsyncThrowingStream<Void, Error> { continuation in
            let navigationTask = Task { @MainActor in
                do {
                    for try await event in events {
                        try Task.checkCancellation()

                        if event == .finished {
                            continuation.yield(())
                            continuation.finish()
                            return
                        }
                    }

                    try Task.checkCancellation()

                    continuation.finish(throwing: AppError.invalidLoad("The webpage stopped loading before it finished."))
                } catch WebPage.NavigationError.failedProvisionalNavigation(let error) {
                    continuation.finish(throwing: AppError(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            let timeoutTask = Task { @MainActor in
                do {
                    try await Task.sleep(for: timeout)

                    continuation.finish(throwing: AppError.timeout("Timed out waiting for the webpage to finish loading."))
                } catch {
                    return
                }
            }

            continuation.onTermination = { _ in
                navigationTask.cancel()
                timeoutTask.cancel()
            }
        }

        for try await _ in completion {
            try Task.checkCancellation()
            return
        }

        try Task.checkCancellation()

        throw AppError.invalidLoad("The webpage stopped loading before it finished.")
    }
}
