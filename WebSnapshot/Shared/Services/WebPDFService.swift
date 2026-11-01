import WebKit

@MainActor
enum WebPDFService {
    static func export(_ webPage:WebPage) async throws -> PDFFileDocument{

        let wait:TimeInterval = 15

        let sleep:UInt64 = 300_000_000

        guard let loadedURL = webPage.url, loadedURL.isSupportedWebURL else {
            throw AppError.invalidLoad("Load a webpage before saving.")
        }

        let source = try await WebExportSource(webPage)

        let originalMediaType = webPage.mediaType

        webPage.mediaType = .screen

        defer {
            webPage.mediaType = originalMediaType
        }

        do{
            try await preparePageForPDFExport(webPage)

            try await waitUntilPageResourcesAreReady(webPage,wait)

            try await Task.sleep(nanoseconds: sleep)

        } catch let error as CancellationError {
            throw error
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.invalidLoad("The webpage did not become ready for export.",error.localizedDescription,error)
        }


        try await source.validate(webPage)

        let data:Data

        do {
            data = try await webPage.exported( as: .pdf( region: .contents,allowTransparentBackground: false ) )
        } catch let error as CancellationError {
            throw error
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.invalidIO("The webpage could not be exported as a PDF.",error.localizedDescription,error)
        }

        try await source.validate(webPage)

        return PDFFileDocument(data)
    }

    static func preparePageForPDFExport(_ webPage:WebPage, maximumScrolls: Int = 60) async throws {

        let clock = ContinuousClock()
        var previousHeight: Double?
        var stableSince: ContinuousClock.Instant?
        var reachedBottom = false

        for _ in 0..<maximumScrolls {
            try Task.checkCancellation()

            try await scrollTowardBottomForPDF(webPage)

            try await Task.sleep(nanoseconds: 150_000_000)

            let position = try await pageScrollPosition(webPage)

            if position.remaining <= 1, position.height == previousHeight {
                let since = stableSince ?? clock.now
                stableSince = since

                if clock.now - since >= .seconds(1) {
                    reachedBottom = true
                    break
                }
            } else {
                stableSince = nil
            }

            previousHeight = position.height
        }

        _ = try await webPage.callJavaScript("window.scrollTo(0, 0); return true;")

        guard reachedBottom else {
            throw AppError.timeout("The webpage kept adding content or was too long to prepare. Wait for it to finish loading and try again.")
        }
    }

    static private func scrollTowardBottomForPDF(_ webPage:WebPage) async throws {

        _ = try await webPage
            .callJavaScript(
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

            const viewportHeight = Math.max(window.innerHeight || 0, 1);
            const scrollHeight = Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0
            );

            const maxScrollY = Math.max(scrollHeight - viewportHeight, 0);

            const nextScrollY = Math.min(
                window.scrollY + Math.max(viewportHeight * 0.85, 320),
                maxScrollY
            );

            window.scrollTo(0, nextScrollY);

            return true;
            """
        )
    }

    static private func pageScrollPosition(_ webPage: WebPage) async throws -> (height: Double, remaining: Double) {
        let result = try await webPage.callJavaScript(
            """
            const viewportHeight = Math.max(window.innerHeight || 0, 1);
            const scrollHeight = Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0
            );

            return { height: scrollHeight, remaining: Math.max(scrollHeight - viewportHeight - window.scrollY, 0) };
            """
        ) as? [String: Double]

        guard let height = result?["height"], let remaining = result?["remaining"] else {
            throw AppError.invalidLoad("The webpage's scroll position could not be determined.")
        }

        return (height, remaining)
    }


    static private func waitUntilPageResourcesAreReady(_ webPage:WebPage,_ timeout: TimeInterval) async throws {

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
