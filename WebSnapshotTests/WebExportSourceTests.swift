import Foundation
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
        try await load(page, "https://example.com/article")
        _ = try await page.callJavaScript("""
            window.scrollTo = function() { history.replaceState({}, '', '/other'); };
            return true;
            """)
        do {
            _ = try await WebService.export(page)
            XCTFail("An export that navigated during preparation must not return PDF data")
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
