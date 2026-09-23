import CoreGraphics
import Foundation
import PDFKit
import XCTest
@testable import WebSnapshot

final class PDFRenderingTests: XCTestCase {
    func testRotatedAndCroppedPagesKeepBothCornerMarkers() throws {
        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &mediaBox, nil))
        context.beginPDFPage(nil)
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 50, y: 50, width: 60, height: 60))
        context.setFillColor(CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        context.fill(CGRect(x: 502, y: 682, width: 60, height: 60))
        context.endPDFPage()
        context.closePDF()

        let document = try XCTUnwrap(PDFDocument(data: data as Data))
        let page = try XCTUnwrap(document.page(at: 0))
        page.setBounds(CGRect(x: 50, y: 50, width: 512, height: 692), for: .cropBox)

        for rotation in [0, 90, 180, 270] {
            page.rotation = rotation
            let image = try LibraryViewService.render(page, 72)
            let swapsDimensions = rotation == 90 || rotation == 270
            XCTAssertEqual(image.width, swapsDimensions ? 692 : 512)
            XCTAssertEqual(image.height, swapsDimensions ? 512 : 692)
            let counts = try markerPixelCounts(image)
            XCTAssertGreaterThan(counts.red, 3_400, "Red marker clipped at \(rotation) degrees")
            XCTAssertGreaterThan(counts.blue, 3_400, "Blue marker clipped at \(rotation) degrees")
        }
    }

    private func markerPixelCounts(_ image: CGImage) throws -> (red: Int, blue: Int) {
        let context = try XCTUnwrap(CGContext(
            data: nil, width: image.width, height: image.height,
            bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = try XCTUnwrap(context.data).assumingMemoryBound(to: UInt8.self)
        var red = 0
        var blue = 0
        for index in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            if pixels[index] > 200 && pixels[index + 1] < 40 && pixels[index + 2] < 40 { red += 1 }
            if pixels[index] < 40 && pixels[index + 1] < 40 && pixels[index + 2] > 200 { blue += 1 }
        }
        return (red, blue)
    }
}
