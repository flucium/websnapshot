import WebKit

final class WebService{
    static func export(_ webPage:WebPage) async throws -> PDFFileDocument{
        let wait:TimeInterval = 15
        
        let sleep:UInt64 = 300_000_000
        
        guard let loadedURL = webPage.url, loadedURL.isSupportedWebURL else {
            throw AppError.invalidLoad("Load a webpage before saving.")
        }
        
        do{
            try await waitUntilPageStopsLoading(webPage,wait)
            
            try await preparePageForPDFExport(webPage)
            
            try await waitUntilPageResourcesAreReady(webPage,wait)
            
            try await Task.sleep(nanoseconds: sleep)
            
        }catch{
            throw AppError.invalidLoad("Invalid page load.")
        }
        
        
        let originalMediaType = webPage.mediaType
        
        webPage.mediaType = .screen
        
        do{
            webPage.mediaType = originalMediaType
        }
        
        let data:Data
        
        do {
            data = try await webPage.exported(as: .pdf(region: .contents, allowTransparentBackground: false))
        }catch{
            throw AppError.invalidIO("Invalid export to PDF.")
        }
        
        let pdfFileDocument:PDFFileDocument = PDFFileDocument(data)
        
        return pdfFileDocument
    }
    
    static func fetch(_ url:URL) throws -> WebPage{
        let webPage:WebPage = WebPage()
        
        webPage.load(url)
        
        return webPage
     }
    
    static private func waitUntilPageStopsLoading(_ webPage:WebPage, _ timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while webPage.isLoading {

            guard Date() < deadline else {
                throw AppError.timeout("Timed out waiting for the page to finish loading.")
            }

            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    
    static private func preparePageForPDFExport(_ webPage:WebPage) async throws {
        _ = try await webPage.callJavaScript(
            """
            document.querySelectorAll('img').forEach((image) => {
                image.setAttribute('loading', 'eager');
                image.setAttribute('decoding', 'sync');
                image.setAttribute('fetchpriority', 'high');

                const dataSrc = image.getAttribute('data-src');
                if (dataSrc && !image.getAttribute('src')) {
                    image.setAttribute('src', dataSrc);
                }

                const dataSrcSet = image.getAttribute('data-srcset');
                if (dataSrcSet && !image.getAttribute('srcset')) {
                    image.setAttribute('srcset', dataSrcSet);
                }
            });

            document.querySelectorAll('iframe[loading="lazy"]').forEach((frame) => {
                frame.setAttribute('loading', 'eager');
            });

            return true;
            """
        )

        for _ in 0..<60 {
            let hasMoreContent = try await scrollTowardBottomForPDF(webPage)

            try await Task.sleep(nanoseconds: 150_000_000)

            if hasMoreContent == false{
                break
            }
        }

        _ = try await webPage.callJavaScript(
            """
            window.scrollTo(0, 0);
            return true;
            """
        )
    }
    
    static private func scrollTowardBottomForPDF(_ webPage:WebPage) async throws -> Bool {
        let result = try await webPage.callJavaScript(
            """
            const viewportHeight = Math.max(window.innerHeight || 0, 1);
            const scrollHeight = Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0
            );

            const maxScrollY = Math.max(scrollHeight - viewportHeight, 0);

            if (maxScrollY <= 0) {
                return false;
            }

            const nextScrollY = Math.min(
                window.scrollY + Math.max(viewportHeight * 0.85, 320),
                maxScrollY
            );

            window.scrollTo(0, nextScrollY);

            return nextScrollY < maxScrollY;
            """
        )

        return result as? Bool ?? false
    }

    
    static private func waitUntilPageResourcesAreReady(_ webPage:WebPage, _ timeout: TimeInterval) async throws {
        
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if try await arePageResourcesReadyForPDF(webPage) {
                return
            }

            guard Date() < deadline else {
                throw AppError.timeout("Timed out waiting for page resources to finish loading.")
            }

            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }
    
    static private func arePageResourcesReadyForPDF(_ webPage:WebPage) async throws -> Bool {
        let result = try await webPage.callJavaScript(
            """
            const images = Array.from(document.images || []);
            const hasPendingImages = images.some((image) => !image.complete);
            const fontsReady = !document.fonts || document.fonts.status === 'loaded';

            return document.readyState === 'complete' && fontsReady && !hasPendingImages;
            """
        )

        return result as? Bool ?? false
    }
}
