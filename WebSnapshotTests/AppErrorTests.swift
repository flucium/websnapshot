import Foundation
import XCTest
@testable import WebSnapshot

final class AppErrorTests: XCTestCase {
    func testEachKindReturnsItsUserMessage() {
        let errors: [(AppError, AppError.Kind, String)] = [
            (.error("Generic message"), .generic, "Generic message"),
            (.system("System message"), .system, "System message"),
            (.invalidLoad("Load message"), .invalidLoad, "Load message"),
            (.invalidURL("URL message"), .invalidURL, "URL message"),
            (.invalidNetwork("Network message"), .network, "Network message"),
            (.invalidIO("I/O message"), .io, "I/O message"),
            (.invalidFileType("File type message"), .invalidFileType, "File type message"),
            (.permissionDenied("Permission message"), .permissionDenied, "Permission message"),
            (.notFound("Not found message"), .notFound, "Not found message"),
            (.timeout("Timeout message"), .timeout, "Timeout message"),
            (.translationFailed("Translation message"), .translation, "Translation message"),
            (.textRecognitionFailed("Recognition message"), .textRecognition, "Recognition message")
        ]

        for (error, kind, message) in errors {
            XCTAssertEqual(error.kind, kind)
            XCTAssertEqual(error.errorDescription, message)
            XCTAssertEqual(error.localizedDescription, message)
        }
    }

    func testWrappingAppErrorPreservesItsClassification() {
        let timeout = AppError.timeout("Timed out")
        let wrapped = AppError(timeout)

        XCTAssertEqual(wrapped.id, timeout.id)
        XCTAssertEqual(wrapped.kind, .timeout)
    }

    func testCancellationIsNotPresentable() {
        XCTAssertNil(AppError.presentable(CancellationError()))
    }

    func testUnderlyingErrorIsKeptForDiagnostics() {
        let underlying = NSError(domain: "TestDomain", code: 42)
        let error = AppError.invalidIO(
            "The file operation failed.",
            "Diagnostic detail",
            underlying
        )

        XCTAssertEqual(error.userMessage, "The file operation failed.")
        XCTAssertEqual(error.diagnosticMessage, "Diagnostic detail")
        XCTAssertEqual(error.underlyingError?.domain, "TestDomain")
        XCTAssertEqual(error.underlyingError?.code, 42)
    }
}
