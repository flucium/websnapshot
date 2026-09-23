import Foundation
import XCTest
@testable import WebSnapshot

@MainActor
final class PDFFileNameTests: XCTestCase {
    func testTitlesKeepDotsAndAlwaysHavePDFExtension() {
        for (title, expected) in [
            "Example.com": "Example.com.pdf",
            "Release 1.2": "Release 1.2.pdf",
            "Report.PDF": "Report.pdf",
            "Report.pdf": "Report.pdf",
            "   ": "page.pdf"
        ] {
            XCTAssertEqual(URL.pdfFileName(title, nil), expected)
        }
        XCTAssertEqual(
            URL.pdfFileName(nil, URL(string: "https://example.com/docs/page")),
            "example.comdocspage.pdf"
        )
    }

    func testRepeatedFixedFolderSavesKeepPDFExtensionAndOriginalContents() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstData = Data("first".utf8)
        let secondData = Data("second".utf8)
        let first = try XCTUnwrap(saveToDirectory("Example.com", nil, PDFFileDocument(firstData), directory))
        let second = try XCTUnwrap(saveToDirectory("Example.com", nil, PDFFileDocument(secondData), directory))

        XCTAssertEqual(first.lastPathComponent, "Example.com.pdf")
        XCTAssertEqual(second.lastPathComponent, "Example.com 2.pdf")
        XCTAssertEqual(try Data(contentsOf: first), firstData)
        XCTAssertEqual(try Data(contentsOf: second), secondData)
    }

    func testLongNamesAndURLFallbackCanBeSavedRepeatedly() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = try XCTUnwrap(URL(string: "https://example.com/" + String(repeating: "path", count: 200)))
        for title in [String(repeating: "a", count: 300),
                      String(repeating: "日本語", count: 100),
                      String(repeating: "👩🏽‍💻", count: 100), ""] {
            var destinations = Set<URL>()
            for index in 1...12 {
                let data = Data("PDF \(index)".utf8)
                let destination = try XCTUnwrap(saveToDirectory(title, url, PDFFileDocument(data), directory))
                XCTAssertLessThanOrEqual(destination.lastPathComponent.utf8.count, 240)
                XCTAssertEqual(destination.pathExtension, "pdf")
                XCTAssertTrue(destinations.insert(destination).inserted)
                XCTAssertEqual(try Data(contentsOf: destination), data)
            }
            XCTAssertEqual(destinations.count, 12)
        }
    }

    func testTruncationPreservesWholeUnicodeCharacters() {
        let character = "👩🏽‍💻"
        let name = URL.pdfFileName(String(repeating: character, count: 100), nil)
        XCTAssertTrue(name.dropLast(4).allSatisfy { String($0) == character })
        XCTAssertFalse(name.dropLast(4).isEmpty)
        // Even a single grapheme longer than the byte budget gets a usable name.
        XCTAssertEqual(URL.pdfFileName("a" + String(repeating: "\u{0301}", count: 300), nil), "page.pdf")
    }
}
