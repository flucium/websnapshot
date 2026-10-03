import CoreGraphics
import CoreText
import Foundation
import PDFKit
import XCTest
@testable import WebSnapshot

@MainActor
final class PDFContentServiceTests: XCTestCase {
    func testExtractsEmbeddedTextFromEveryPage() async throws {
        let fixture = try ContentSearchFixture(["First page text", "Second page text"])
        defer { fixture.remove() }

        let text = try await PDFContentService(recognize: { _ in
            throw AppError.error("Embedded text should not trigger OCR")
        }).text(fixture.url)

        XCTAssertTrue(text.contains("First page text"))
        XCTAssertTrue(text.contains("Second page text"))
        XCTAssertLessThan(try XCTUnwrap(text.range(of: "First")).lowerBound,
                          try XCTUnwrap(text.range(of: "Second")).lowerBound)
    }

    func testMixedPDFUsesOCRForImagePageAndKeepsEmbeddedText() async throws {
        let fixture = try ContentSearchFixture(
            ["Embedded page text", "Searchable scanned content"], imagePages: [1]
        )
        defer { fixture.remove() }
        let document = try XCTUnwrap(PDFDocument(url: fixture.url))
        XCTAssertTrue(document.page(at: 1)?.string?.isEmpty ?? true)

        let text = try await PDFContentService().text(fixture.url)

        XCTAssertTrue(text.contains("Embedded page text"))
        XCTAssertTrue(text.localizedCaseInsensitiveContains("scanned content"), text)
    }

    func testOCRFallbackIsOnlyUsedForPagesWithoutText() async throws {
        let fixture = try ContentSearchFixture(["Embedded page text", "Scanned content"], imagePages: [1])
        defer { fixture.remove() }
        let service = PDFContentService(recognize: { _ in "Recognized image text" })

        let text = try await service.text(fixture.url)

        XCTAssertTrue(text.contains("Embedded page text"))
        XCTAssertTrue(text.contains("Recognized image text"))
        XCTAssertFalse(text.contains("Scanned content"))
    }

    func testBlankPDFProducesAnEmptyCacheableResult() async throws {
        let fixture = try ContentSearchFixture([""])
        defer { fixture.remove() }
        let text = try await PDFContentService().text(fixture.url)
        XCTAssertEqual(text, "")
    }

    func testInvalidPDFIsRejected() async throws {
        let fixture = try ContentSearchFixture(["Original"])
        defer { fixture.remove() }
        try Data("Not a PDF".utf8).write(to: fixture.url)

        do {
            _ = try await PDFContentService().text(fixture.url)
            XCTFail("Invalid PDF should be rejected")
        } catch let error as AppError {
            XCTAssertEqual(error.kind, .invalidFileType)
        }
    }

    func testCancelledExtractionDoesNotProduceText() async throws {
        let fixture = try ContentSearchFixture(["Original"])
        defer { fixture.remove() }
        let task = Task { try await PDFContentService().text(fixture.url) }
        task.cancel()
        do {
            _ = try await task.value
            XCTFail("Cancelled extraction should not produce text")
        } catch is CancellationError {}
    }

    func testFingerprintDetectsAtomicReplacementWithSameSizeAndDate() throws {
        let fixture = try ContentSearchFixture(["Original"])
        defer { fixture.remove() }
        let original = try PDFContentService.fingerprint(fixture.url)
        let attributes = try FileManager.default.attributesOfItem(atPath: fixture.url.path)
        let data = try Data(contentsOf: fixture.url)
        try data.write(to: fixture.url, options: .atomic)
        try FileManager.default.setAttributes(
            [.modificationDate: try XCTUnwrap(attributes[.modificationDate])],
            ofItemAtPath: fixture.url.path
        )
        XCTAssertNotEqual(try PDFContentService.fingerprint(fixture.url), original)
    }
}

struct ContentSearchFixture {
    let directory: URL
    let url: URL

    init(_ pages: [String], imagePages: Set<Int> = []) throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        url = directory.appendingPathComponent("Report.pdf")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Self.data(pages, imagePages: imagePages).write(to: url)
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    nonisolated static func data(_ pages: [String], imagePages: Set<Int> = []) throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 612, height: 200)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        for (index, text) in pages.enumerated() {
            context.beginPDFPage(nil)
            if imagePages.contains(index) {
                let imageContext = try XCTUnwrap(CGContext(
                    data: nil, width: 1224, height: 400, bitsPerComponent: 8, bytesPerRow: 0,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
                ))
                imageContext.setFillColor(CGColor(gray: 1, alpha: 1))
                imageContext.fill(CGRect(x: 0, y: 0, width: 1224, height: 400))
                draw(text, imageContext, 60, 220, 72)
                context.draw(try XCTUnwrap(imageContext.makeImage()), in: box)
            } else if text.isEmpty == false {
                draw(text, context, 30, 110, 30)
            }
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    nonisolated private static func draw(_ text: String, _ context: CGContext,
                                         _ x: CGFloat, _ y: CGFloat, _ fontSize: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica" as CFString, fontSize, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1)
        ]
        context.textPosition = CGPoint(x: x, y: y)
        CTLineDraw(CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes)), context)
    }
}
