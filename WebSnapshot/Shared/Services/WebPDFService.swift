import WebKit

@MainActor
enum WebPDFService {
    nonisolated struct Limits: Sendable {
        var preparationTimeout: Duration = .seconds(60)
        var resourceTimeout: Duration = .seconds(30)
        var stallTimeout: Duration = .seconds(5)
        var settlingTime: Duration = .seconds(2)
        var scrollInterval: Duration = .milliseconds(150)
        var maximumHeight: Double = 250_000
    }

    static func export(_ webPage:WebPage, limits: Limits = Limits(), onProgress: (WebPDFExportState) -> Void = { _ in }) async throws -> PDFFileDocument{

        let clock = ContinuousClock()
        let started = clock.now
        let preparationDeadline = started + limits.preparationTimeout
        var resourceDeadline: ContinuousClock.Instant?

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
            while true {
                let height = try await preparePageForPDFExport(webPage, limits, started, preparationDeadline, onProgress) {
                    try await source.validate(webPage)
                }

                let deadline = resourceDeadline ?? clock.now + limits.resourceTimeout
                resourceDeadline = deadline

                try await waitUntilPageResourcesAreReady(webPage, deadline, started, height, onProgress) {
                    try await source.validate(webPage)
                }

                try await Task.sleep(for: .milliseconds(300))
                try await source.validate(webPage)

                let position = try await pageScrollPosition(webPage)
                if abs(position.height - height) <= 1 {
                    break
                }
            }

        } catch let error as CancellationError {
            throw error
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.invalidLoad("The webpage did not become ready for export.",error.localizedDescription,error)
        }


        try await source.validate(webPage)

        let position = try await pageScrollPosition(webPage)
        onProgress(WebPDFExportState(phase: .exporting, elapsed: elapsed(started), height: position.height))

        try Task.checkCancellation()

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

    @discardableResult
    static func preparePageForPDFExport(_ webPage:WebPage, limits: Limits = Limits(), onProgress: (WebPDFExportState) -> Void = { _ in }) async throws -> Double {
        let started = ContinuousClock().now

        return try await preparePageForPDFExport(webPage, limits, started, started + limits.preparationTimeout, onProgress) {}
    }

    static private func preparePageForPDFExport(_ webPage: WebPage, _ limits: Limits, _ started: ContinuousClock.Instant, _ deadline: ContinuousClock.Instant, _ onProgress: (WebPDFExportState) -> Void, _ validate: () async throws -> Void) async throws -> Double {

        let clock = ContinuousClock()
        var previous: (height: Double, remaining: Double, offset: Double)?
        var stableSince: ContinuousClock.Instant?
        var lastProgress = clock.now

        while true {
            try Task.checkCancellation()
            try await validate()

            guard clock.now < deadline else {
                throw AppError.timeout("The webpage took too long to prepare. It may still be adding content.")
            }

            let position = try await pageScrollPosition(webPage)

            guard position.height <= limits.maximumHeight else {
                throw AppError.invalidLoad("The webpage exceeded the supported height for a single PDF. No PDF was saved.")
            }

            onProgress(WebPDFExportState(elapsed: elapsed(started), height: position.height))
            try Task.checkCancellation()

            let unchanged = previous.map { abs(position.height - $0.height) <= 1 } ?? false

            if position.remaining <= 1, unchanged {
                let since = stableSince ?? clock.now
                stableSince = since

                if clock.now - since >= limits.settlingTime {
                    try await validate()
                    _ = try await webPage.callJavaScript("window.scrollTo(0, 0); return true;")
                    try Task.checkCancellation()
                    return position.height
                }
            } else {
                stableSince = nil
            }

            if let previous, abs(position.offset - previous.offset) > 1 || !unchanged {
                lastProgress = clock.now
            }

            if position.remaining > 1, clock.now - lastProgress >= limits.stallTimeout {
                throw AppError.timeout("The webpage stopped making scroll progress before reaching the bottom.")
            }

            previous = position

            try await scrollTowardBottomForPDF(webPage)
            try await Task.sleep(for: limits.scrollInterval)
        }
    }

    static private func scrollTowardBottomForPDF(_ webPage:WebPage) async throws {

        _ = try await webPage
            .callJavaScript(
            """
            document.querySelectorAll('img:not([decoding="sync"]), img[loading="lazy"], img[data-src]:not([src]), img[data-src][src=""], img[data-srcset]:not([srcset]), img[data-srcset][srcset=""]').forEach((image) => {
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

    static private func pageScrollPosition(_ webPage: WebPage) async throws -> (height: Double, remaining: Double, offset: Double) {
        let result = try await webPage.callJavaScript(
            """
            const viewportHeight = Math.max(window.innerHeight || 0, 1);
            const scrollHeight = Math.max(
                document.body ? document.body.scrollHeight : 0,
                document.documentElement ? document.documentElement.scrollHeight : 0
            );

            return { height: scrollHeight, remaining: Math.max(scrollHeight - viewportHeight - window.scrollY, 0), offset: window.scrollY };
            """
        ) as? [String: Double]

        guard let height = result?["height"], let remaining = result?["remaining"], let offset = result?["offset"], height.isFinite, remaining.isFinite, offset.isFinite, height >= 0 else {
            throw AppError.invalidLoad("The webpage's scroll position could not be determined.")
        }

        return (height, remaining, offset)
    }


    static private func waitUntilPageResourcesAreReady(_ webPage: WebPage, _ deadline: ContinuousClock.Instant, _ started: ContinuousClock.Instant, _ height: Double, _ onProgress: (WebPDFExportState) -> Void, _ validate: () async throws -> Void) async throws {
        let clock = ContinuousClock()

        while true {
            try Task.checkCancellation()
            try await validate()

            let resources = try await pageResources(webPage)
            onProgress(WebPDFExportState(phase: .resources, elapsed: elapsed(started), height: height, pendingImages: resources.pendingImages, waitingForFonts: !resources.fontsReady))

            try Task.checkCancellation()

            if resources.ready {
                return
            }

            guard clock.now < deadline else {
                throw AppError.timeout("Images or fonts did not finish loading in time. No PDF was saved.")
            }

            try await Task.sleep(for: .milliseconds(200))
        }
    }

    static private func pageResources(_ webPage: WebPage) async throws -> (ready: Bool, pendingImages: Int, fontsReady: Bool) {

        let result = try await webPage.callJavaScript(
            """
            const images = Array.from(document.images || []);
            const pendingImages = images.filter((image) => !image.complete).length;
            const fontsReady = !document.fonts || document.fonts.status === 'loaded';

            return { ready: document.readyState === 'complete' && fontsReady && pendingImages === 0, pendingImages, fontsReady };
            """
        ) as? [String: Any]

        guard let ready = result?["ready"] as? Bool, let pendingImages = result?["pendingImages"] as? Int, let fontsReady = result?["fontsReady"] as? Bool else {
            throw AppError.invalidLoad("The webpage's resource loading status could not be determined.")
        }

        return (ready, pendingImages, fontsReady)
    }

    static private func elapsed(_ started: ContinuousClock.Instant) -> TimeInterval {
        let duration = started.duration(to: ContinuousClock().now).components

        return Double(duration.seconds) + Double(duration.attoseconds) / 1_000_000_000_000_000_000
    }
}
