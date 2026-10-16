import Foundation
import XCTest
@testable import WebSnapshot

final class FileErrorHandlingTests: XCTestCase {
    func testICloudTrashIsRecognized() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let trash = directory.appendingPathComponent("Library/Mobile Documents/.Trash/Storage", isDirectory: true)

        XCTAssertTrue(FileIO.isInTrash(trash))
        XCTAssertTrue(FileIO.isInTrash(trash.appendingPathComponent("Article.pdf")))
    }

    func testFolderNamedTrashInsideICloudDriveIsNotTreatedAsCloudTrash() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let folder = directory.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/.Trash/Storage", isDirectory: true)

        XCTAssertFalse(FileIO.isInTrash(folder))
    }

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
