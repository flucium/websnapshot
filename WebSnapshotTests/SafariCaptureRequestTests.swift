import Foundation
import XCTest
@testable import WebSnapshot

final class SafariCaptureRequestTests: XCTestCase {
    func testNativeMessageAndOpenURLPreserveQueryAndFragment() throws {
        let address = "https://example.com/日本語?a=1&redirect=https%3A%2F%2Fexample.com%2F%3Fx%3D2&plus=a+b#part-2"
        let id = UUID()
        let request = try SafariCaptureRequest(message: [
            "type": "save-page", "id": id.uuidString, "url": address,
        ])
        XCTAssertEqual(try SafariCaptureRequest(openURL: request.openURL), request)
        XCTAssertEqual(request.id, id)
        XCTAssertEqual(request.url, URL(string: address))
    }

    func testRejectsNonWebURLsAndEmbeddedCredentials() {
        for address in ["file:///tmp/private.pdf", "javascript:alert(1)", "about:blank",
                        "https:///", "https://user:password@example.com", "websnapshot://capture"] {
            XCTAssertThrowsError(try SafariCaptureRequest(message: [
                "type": "save-page", "id": UUID().uuidString, "url": address,
            ]), address)
        }
    }

    func testRejectsMalformedOrAmbiguousCommands() throws {
        let request = try SafariCaptureRequest(id: UUID(), url: XCTUnwrap(URL(string: "https://example.com")))
        for address in [
            "websnapshot://other?id=\(request.id)&url=https://example.com",
            "websnapshot://capture?id=bad&url=https://example.com",
            request.openURL.absoluteString + "&url=https://other.example.com",
            request.openURL.absoluteString + "#extra",
            "websnapshot://user@capture?id=\(request.id)&url=https://example.com",
        ] {
            XCTAssertThrowsError(try SafariCaptureRequest(openURL: XCTUnwrap(URL(string: address))))
        }
        XCTAssertThrowsError(try SafariCaptureRequest(message: [
            "type": "delete", "id": request.id.uuidString, "url": request.url.absoluteString,
        ]))
    }
}
