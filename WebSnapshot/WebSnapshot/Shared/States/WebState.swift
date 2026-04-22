import Combine
import WebKit

@MainActor
class WebState: ObservableObject {
    @Published var error: AppError?
    
    @Published var webPage = WebPage()
    
    @Published var urlString: String = String()
    
    @Published var isSaving = false
    
    @Published var pdfFileDocument: PDFFileDocument?
    

    func load() {
        guard let url = URL.normalized(urlString) else {
            error = .invalidURL
            return
        }

        error = nil
        
        webPage.load(url)
    }

    func clear() {
        webPage = WebPage()
        
        urlString = String()
        
        pdfFileDocument = nil
        
        error = nil
    }

    func save() async ->  Bool {
        guard let loadedURL = webPage.url, loadedURL.isSupportedWebURL else {
        
            error = AppError.display(message: "Load a webpage before saving.")
        
            return false
        }

        isSaving = true
        
        error = nil

        defer {
            isSaving = false
        }

        do {
            if let originalPDFData = try await sourcePDFDataIfAvailable(loadedURL) {
                pdfFileDocument = PDFFileDocument( originalPDFData)
                
                return true
            }

            try await waitUntilPageStopsLoading(15)
            
            try await preparePageForPDFExport()

            try await waitUntilPageResourcesAreReady( 15)
            
            try await Task.sleep(nanoseconds: 300_000_000)

            let originalMediaType = webPage.mediaType
            
            webPage.mediaType = .screen

            defer {
                webPage.mediaType = originalMediaType
            }

            let data = try await webPage.exported(as: .pdf(region: .contents, allowTransparentBackground: false))

            pdfFileDocument = PDFFileDocument( data)
            
            return true
            
        } catch {
            self.error = AppError( error)
            
            return false
        }
    }

    private func waitUntilPageStopsLoading(_ timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)

        while webPage.isLoading {

            guard Date() < deadline else {
                throw AppError.display(message: "Timed out waiting for the page to finish loading.")
            }

            try await Task.sleep(nanoseconds: 150_000_000)
        }
    }

    private func preparePageForPDFExport() async throws {
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
            let hasMoreContent = try await scrollTowardBottomForPDF()

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

    private func scrollTowardBottomForPDF() async throws -> Bool {
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

    private func waitUntilPageResourcesAreReady(_ timeout: TimeInterval) async throws {
        
        let deadline = Date().addingTimeInterval(timeout)

        while true {
            if try await arePageResourcesReadyForPDF() {
                return
            }

            guard Date() < deadline else {
                throw AppError.display(message: "Timed out waiting for page resources to finish loading.")
            }

            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    private func arePageResourcesReadyForPDF() async throws -> Bool {
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

    private func sourcePDFDataIfAvailable(_ url: URL) async throws -> Data? {
        guard url.isLikelyPDFResource else {
            return nil
        }

        let (data, response) = try await URLSession.shared.data(from: url)

        guard
            data.starts(with: Data("%PDF-".utf8))   ||
                response.mimeType?.lowercased() == "application/pdf"    ||
                (response.suggestedFilename?.lowercased())?.hasSuffix(".pdf") == true
        else {
            return nil
        }

        return data
    }
}
