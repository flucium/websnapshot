import Foundation
import XCTest
@testable import WebSnapshot

final class FileErrorHandlingTests: XCTestCase {
    func testInvalidBookmarkDataIsReportedAsAnError() {
        var isStale = false

        XCTAssertThrowsError(
            try URL.resolveSecurityScopedBookmarkData(
                Data([0x00, 0x01]),
                &isStale
            )
        )
    }

    func testEmptyDocumentDataIsRejected() {
        XCTAssertThrowsError(try PDFFileDocument.validatedData(nil)) { error in
            XCTAssertEqual((error as? AppError)?.kind, .invalidFileType)
        }

        XCTAssertThrowsError(try PDFFileDocument.validatedData(Data())) { error in
            XCTAssertEqual((error as? AppError)?.kind, .invalidFileType)
        }
    }

    func testUnreadablePDFDataIsRejected() {
        let invalidData = Data("not a PDF".utf8)

        XCTAssertThrowsError(try DirectoryPDFView.document(invalidData)) { error in
            XCTAssertEqual((error as? AppError)?.kind, .invalidFileType)
        }
    }
}
