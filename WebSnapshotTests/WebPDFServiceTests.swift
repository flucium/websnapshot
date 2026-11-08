import Foundation
import PDFKit
import WebKit
import XCTest

@testable import WebSnapshot

@MainActor
final class WebPDFServiceTests: XCTestCase {
    func testPreparationReachesTheBottomAfterMoreThanSixtyScrolls() async throws {
        let page = try await makePage(height: 35_000)
        var heights: [Double] = []

        try await WebPDFService.preparePageForPDFExport(page, limits: limits()) {
            heights.append($0.height)
        }

        let scrolls = try await page.callJavaScript("return window.testScrolls;") as? Int
        let reachedBottom = try await page.callJavaScript("return window.testReachedBottom;") as? Bool
        XCTAssertGreaterThan(try XCTUnwrap(scrolls), 60)
        XCTAssertEqual(reachedBottom, true)
        XCTAssertEqual(heights.first, 35_000)
    }

    func testLongHTMLExportsItsEndingText() async throws {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)
        try await WebService.waitForNavigation(page.load(
            html: "<html><body><div id='article'>ArticleStart</div><p>ArticleEndingMarker</p></body></html>",
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid/long-article"))
        ))
        _ = try await page.callJavaScript("""
            const step = Math.max((window.innerHeight || 0) * 0.85, 320);
            document.getElementById('article').style.height = `${step * 75}px`;
            const scroll = window.scrollTo.bind(window);
            window.testScrolls = 0;
            window.scrollTo = function(x, y) {
                window.testScrolls += 1;
                scroll(x, y);
            };
            return true;
            """)

        let document = try await WebPDFService.export(page, limits: limits())
        let pdf = try XCTUnwrap(PDFDocument(data: document.data))
        let scrolls = try await page.callJavaScript("return window.testScrolls;") as? Int

        XCTAssertGreaterThan(try XCTUnwrap(scrolls), 60)
        XCTAssertTrue(pdf.string?.contains("ArticleEndingMarker") == true)
    }

    func testGrowingPageStopsAtTheTimeLimitWithoutReturningAPDF() async throws {
        let page = try await makePage()
        _ = try await page.callJavaScript("""
            window.scrollTo = function(x, y) {
                window.testOffset = y;
                window.testHeight += 1000;
            };
            return true;
            """)
        var settings = limits()
        settings.preparationTimeout = .milliseconds(100)
        settings.maximumHeight = 1_000_000

        do {
            _ = try await WebPDFService.export(page, limits: settings)
            XCTFail("A growing page must not be saved as a complete PDF")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .timeout)
            XCTAssertTrue((error as? AppError)?.userMessage.contains("too long") == true)
        }
    }

    func testHeightLimitStopsPreparationBeforePDFGeneration() async throws {
        let page = try await makePage(height: 5000)
        var settings = limits()
        settings.maximumHeight = 4000
        var phases: [WebPDFExportState.Phase] = []

        do {
            _ = try await WebPDFService.export(page, limits: settings) { phases.append($0.phase) }
            XCTFail("An oversized page must not produce a partial PDF")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .invalidLoad)
            XCTAssertTrue((error as? AppError)?.userMessage.contains("height") == true)
        }

        XCTAssertFalse(phases.contains(.exporting))
    }

    func testPageThatCannotScrollReportsStalledProgress() async throws {
        let page = try await makePage(height: 3000)
        _ = try await page.callJavaScript("window.scrollTo = function() {}; return true;")
        var settings = limits()
        settings.stallTimeout = .milliseconds(40)

        do {
            try await WebPDFService.preparePageForPDFExport(page, limits: settings)
            XCTFail("A stuck scrollbar must not wait for the full preparation timeout")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .timeout)
            XCTAssertTrue((error as? AppError)?.userMessage.contains("scroll progress") == true)
        }
    }

    func testPendingImagesAndFontsReportAResourceTimeout() async throws {
        for script in [
            "Object.defineProperty(document, 'images', { value: [{ complete: false }] });",
            "Object.defineProperty(document, 'fonts', { value: { status: 'loading' } });"
        ] {
            let page = try await makePage()
            _ = try await page.callJavaScript("\(script) return true;")
            var settings = limits()
            settings.resourceTimeout = .milliseconds(30)
            var progress: WebPDFExportState?

            do {
                _ = try await WebPDFService.export(page, limits: settings) { progress = $0 }
                XCTFail("Pending resources must not be silently omitted")
            } catch {
                XCTAssertEqual((error as? AppError)?.kind, .timeout)
                XCTAssertTrue((error as? AppError)?.userMessage.contains("Images or fonts") == true)
            }

            XCTAssertEqual(progress?.phase, .resources)
            XCTAssertTrue(progress?.pendingImages == 1 || progress?.waitingForFonts == true)
        }
    }

    func testResourcesThatIncreasePageHeightTriggerAnotherPreparationPass() async throws {
        let page = try await makePage()
        _ = try await page.callJavaScript("""
            window.testImageReady = false;
            Object.defineProperty(document, 'images', {
                value: [{ get complete() { return window.testImageReady; } }]
            });
            return true;
            """)
        var visitedExpandedPage = false
        var scheduledExpansion = false
        var expansionTask: Task<Void, Error>?
        var phases: [WebPDFExportState.Phase] = []

        let document = try await WebPDFService.export(page, limits: limits()) {
            phases.append($0.phase)
            if $0.phase == .resources, !scheduledExpansion {
                scheduledExpansion = true
                expansionTask = Task {
                    _ = try await page.callJavaScript("window.testHeight = 5000; window.testImageReady = true; return true;")
                }
            }
            if $0.phase == .preparing, $0.height == 5000 {
                visitedExpandedPage = true
            }
        }

        try await expansionTask?.value

        XCTAssertTrue(visitedExpandedPage)
        XCTAssertTrue(scheduledExpansion)
        XCTAssertNotNil(PDFDocument(data: document.data))
        XCTAssertEqual(phases.last, .exporting)
    }

    func testCancellingPreparationRestoresMediaAndReturnsNoPDF() async throws {
        let page = try await makePage(height: 30_000)
        page.mediaType = .print
        var task: Task<PDFFileDocument, Error>?
        task = Task {
            try await WebPDFService.export(page, limits: limits()) { _ in
                task?.cancel()
            }
        }

        do {
            _ = try await task?.value
            XCTFail("Cancellation must not return PDF data")
        } catch {
            XCTAssertNil(AppError.presentable(error))
        }

        XCTAssertEqual(page.mediaType, .print)
    }

    func testCancellingResourceWaitDoesNotWaitForItsDeadline() async throws {
        let page = try await makePage()
        _ = try await page.callJavaScript("Object.defineProperty(document, 'images', { value: [{ complete: false }] }); return true;")
        var reachedResources = false
        var task: Task<PDFFileDocument, Error>?
        task = Task {
            try await WebPDFService.export(page, limits: limits()) { progress in
                if progress.phase == .resources {
                    reachedResources = true
                    task?.cancel()
                }
            }
        }

        do {
            _ = try await task?.value
            XCTFail("Cancelling a resource wait must not return a PDF")
        } catch {
            XCTAssertNil(AppError.presentable(error))
        }

        XCTAssertTrue(reachedResources)
    }

    private func limits() -> WebPDFService.Limits {
        var settings = WebPDFService.Limits()
        settings.preparationTimeout = .seconds(5)
        settings.resourceTimeout = .seconds(2)
        settings.scrollInterval = .milliseconds(1)
        settings.settlingTime = .milliseconds(10)
        return settings
    }

    private func makePage(height: Double = 1000) async throws -> WebPage {
        var configuration = WebPage.Configuration()
        configuration.websiteDataStore = .nonPersistent()
        let page = WebPage(configuration: configuration)
        try await WebService.waitForNavigation(page.load(
            html: "<html><head><title>Article</title></head><body>Article content</body></html>",
            baseURL: try XCTUnwrap(URL(string: "https://example.invalid/article"))
        ))
        _ = try await page.callJavaScript("""
            window.testHeight = height;
            window.testOffset = 0;
            window.testScrolls = 0;
            window.testReachedBottom = false;
            Object.defineProperty(window, 'innerHeight', { value: 500 });
            Object.defineProperty(window, 'scrollY', { get: () => window.testOffset });
            Object.defineProperty(document.body, 'scrollHeight', { get: () => window.testHeight });
            Object.defineProperty(document.documentElement, 'scrollHeight', { get: () => window.testHeight });
            window.scrollTo = function(x, y) {
                window.testScrolls += 1;
                window.testOffset = Math.min(y, window.testHeight - window.innerHeight);
                window.testReachedBottom ||= window.testOffset >= window.testHeight - window.innerHeight;
            };
            return true;
            """, arguments: ["height": height])
        return page
    }
}
