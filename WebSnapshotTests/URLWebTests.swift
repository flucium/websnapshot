import Foundation
import XCTest
@testable import WebSnapshot

final class URLWebTests: XCTestCase {
    func testAddsHTTPSWhenSchemeIsMissing() {
        let url = URL.supportedWebURL("example.com/path")

        XCTAssertEqual(url?.absoluteString, "https://example.com/path")
    }

    func testRejectsUnsupportedAndMalformedAddresses() {
        XCTAssertNil(URL.supportedWebURL(""))
        XCTAssertNil(URL.supportedWebURL("https://"))
        XCTAssertNil(URL.supportedWebURL("file:///tmp/example.pdf"))
    }

    func testIPv6LiteralsAreAcceptedByFetchAndSafariCaptureValidation() throws {
        for address in ["http://[::1]/", "https://[2001:db8::1]:8443/article",
                        "http://[::ffff:192.0.2.1]/", "http://[fe80::1%25en0]/"] {
            let url = try XCTUnwrap(URL.supportedWebURL(address), address)
            XCTAssertTrue(url.isSupportedWebURL, address)
            XCTAssertNoThrow(try SafariCaptureRequest(id: UUID(), url: url))
        }
        XCTAssertEqual(URL.supportedWebURL("[::1]:8080/page")?.absoluteString,
                       "https://[::1]:8080/page")
    }

    func testMalformedIPLiteralIsRejected() {
        for address in ["http://[not-an-ip]/", "http://[1:2:3]/", "http://[::gg]/", "http://[::1%25]/", "http://[localhost]/", "http://[127.0.0.1]/", "https://[example.com]/"] {
            XCTAssertNil(URL.supportedWebURL(address), address)
        }
    }

    func testSingleLabelAndTrailingDotHostsAreAccepted() throws {
        for address in ["http://nas/", "https://intranet:8443/article", "https://example.com./", "http://nas./"] {
            let url = try XCTUnwrap(URL.supportedWebURL(address), address)
            XCTAssertEqual(url.absoluteString, address)
            XCTAssertTrue(url.isSupportedWebURL, address)
            XCTAssertNoThrow(try SafariCaptureRequest(id: UUID(), url: url))
        }
        XCTAssertEqual(URL.supportedWebURL("nas/article")?.absoluteString, "https://nas/article")
    }

    func testEmptyAndMalformedHostLabelsAreRejected() {
        for address in ["http://./", "http://../", "https://example..com/", "https://example.com../", "http://-nas/", "http://nas-/", "https://-example.com/", "http://na_s/"] {
            XCTAssertNil(URL.supportedWebURL(address), address)
        }
    }

    func testInvalidAddressRemainsInvalidURLError() async {
        do {
            _ = try await FetchViewService.fetch("https://")
            XCTFail("Expected an invalid URL error")
        } catch let error as AppError {
            XCTAssertEqual(error.kind, .invalidURL)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
