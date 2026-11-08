import Foundation
import PDFKit
import WebKit
import XCTest
@testable import WebSnapshot

@MainActor
final class WebExportSourceTests: XCTestCase {
    func testUnchangedDocumentRemainsValid() async throws {
        let page = WebPage()
        try await load(page, "https://example.com/article")
        let source = try await WebExportSource(page)
        try await source.validate(page)
    }

    func testDifferentDocumentAtSameURLInvalidatesExport() async throws {
        let page = WebPage()
        try await load(page, "https://example.com/article")
        let source = try await WebExportSource(page)
        try await load(page, "https://example.com/article")
        await assertInvalid(source, page)
    }

    func testNavigationAwayAndBackInvalidatesExport() async throws {
        let page = WebPage()
        try await load(page, "https://example.com/article")
        let source = try await WebExportSource(page)
        try await load(page, "https://example.com/other")
        try await load(page, "https://example.com/article")
        await assertInvalid(source, page)
    }

    func testSameDocumentURLChangeInvalidatesExport() async throws {
        let page = WebPage()
        try await load(page, "https://example.com/article")
        let source = try await WebExportSource(page)
        _ = try await page.callJavaScript("history.pushState({}, '', '/other'); return true;")
        await assertInvalid(source, page)
    }

    func testExportRejectsNavigationTriggeredDuringPagePreparation() async throws {
        let page = WebPage()
        page.mediaType = .print
        try await load(page, "https://example.com/article")
        _ = try await page.callJavaScript("""
            window.scrollTo = function() { history.replaceState({}, '', '/other'); };
            return true;
            """)
        do {
            _ = try await WebPDFService.export(page)
            XCTFail("An export that navigated during preparation must not return PDF data")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .invalidLoad)
        }
        XCTAssertEqual(page.mediaType, .print)
    }

    func testExportUsesScreenStylesAndRestoresOriginalMediaType() async throws {
        let page = WebPage()
        page.mediaType = .print
        try await WebService.waitForNavigation(page.load(
            html: """
                <html><head><style>
                @media screen { #print-content { display: none; } }
                @media print { #screen-content { display: none; } }
                </style></head><body>
                <div id="screen-content">ScreenContent</div>
                <div id="print-content">PrintContent</div>
                </body></html>
                """,
            baseURL: try XCTUnwrap(URL(string: "https://example.com/article"))
        ))

        let exported = try await WebPDFService.export(page)
        let document = try XCTUnwrap(PDFDocument(data: exported.data))
        let text = try XCTUnwrap(document.string)

        XCTAssertTrue(text.contains("ScreenContent"))
        XCTAssertFalse(text.contains("PrintContent"))
        XCTAssertEqual(page.mediaType, .print)
    }

    func testPreparationVisitsContentAddedAfterReachingTheBottom() async throws {
        let page = WebPage()
        try await load(page, "https://example.com/article")
        _ = try await page.callJavaScript("""
            window.testHeight = 1000;
            window.testPosition = 0;
            window.testExpanded = false;
            window.testVisitedExpansion = false;
            let scheduled = false;
            Object.defineProperty(window, 'innerHeight', { value: 500 });
            Object.defineProperty(window, 'scrollY', { get: () => window.testPosition });
            Object.defineProperty(document.body, 'scrollHeight', { get: () => window.testHeight });
            Object.defineProperty(document.documentElement, 'scrollHeight', { get: () => window.testHeight });
            window.scrollTo = function(x, y) {
                window.testPosition = Math.min(y, window.testHeight - window.innerHeight);
                if (window.testPosition >= window.testHeight - window.innerHeight) {
                    if (window.testExpanded) window.testVisitedExpansion = true;
                    if (!scheduled) {
                        scheduled = true;
                        setTimeout(() => {
                            window.testHeight += 1000;
                            window.testExpanded = true;
                        }, 400);
                    }
                }
            };
            return true;
            """)

        try await WebPDFService.preparePageForPDFExport(page)

        let visited = try await page.callJavaScript("return window.testVisitedExpansion;") as? Bool
        XCTAssertEqual(visited, true)
    }

    func testExportPreparesResourcesUsingScreenStyles() async throws {
        let page = WebPage()
        page.mediaType = .print
        try await load(page, "https://example.com/article")
        _ = try await page.callJavaScript("""
            window.testPreparedForPrint = false;
            const scroll = window.scrollTo.bind(window);
            window.scrollTo = function(x, y) {
                window.testPreparedForPrint ||= window.matchMedia('print').matches;
                scroll(x, y);
            };
            return true;
            """)

        _ = try await WebPDFService.export(page)

        let preparedForPrint = try await page.callJavaScript("return window.testPreparedForPrint;") as? Bool
        XCTAssertEqual(preparedForPrint, false)
        XCTAssertEqual(page.mediaType, .print)
    }

    func testPreparationRejectsContentThatKeepsGrowingAtTheHeightLimit() async throws {
        let page = WebPage()
        try await load(page, "https://example.com/article")
        _ = try await page.callJavaScript("""
            window.testHeight = 1000;
            window.testPosition = 0;
            Object.defineProperty(window, 'innerHeight', { value: 500 });
            Object.defineProperty(window, 'scrollY', { get: () => window.testPosition });
            Object.defineProperty(document.body, 'scrollHeight', { get: () => window.testHeight });
            Object.defineProperty(document.documentElement, 'scrollHeight', { get: () => window.testHeight });
            window.scrollTo = function(x, y) {
                window.testPosition = y;
                window.testHeight += 1000;
            };
            return true;
            """)

        var limits = WebPDFService.Limits()
        limits.maximumHeight = 3500

        do {
            try await WebPDFService.preparePageForPDFExport(page, limits: limits)
            XCTFail("An incomplete scroll must not be treated as a prepared page")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .invalidLoad)
        }
    }

    private func load(_ page: WebPage, _ address: String) async throws {
        try await WebService.waitForNavigation(page.load(
            html: "<html><head><title>Article</title></head><body>Content</body></html>",
            baseURL: try XCTUnwrap(URL(string: address))
        ))
    }

    private func assertInvalid(_ source: WebExportSource, _ page: WebPage) async {
        do {
            try await source.validate(page)
            XCTFail("Changed content must not be saved as the original document")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .invalidLoad)
        }
    }
}
