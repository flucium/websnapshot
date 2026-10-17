import Foundation
import Combine
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryTranslationStateTests: XCTestCase {
    func testSharedStatePublishesChangesToLibraryView() {
        let state = LibraryViewState()
        let sharedState: LibraryState = state
        var changed = false
        let observation = state.objectWillChange.sink {
            changed = true
        }
        defer { observation.cancel() }

        sharedState.currentPageIndex = 3
        XCTAssertTrue(changed)
        XCTAssertEqual(state.currentPageIndex, 3)

        changed = false
        state.searchText = "Article"
        XCTAssertTrue(changed)

        let error = AppError.error("The PDF could not be opened.")
        LibraryPDFView.Coordinator(sharedState).present(error)
        XCTAssertEqual(state.errorTitle, "PDF Could Not Be Opened")
        XCTAssertEqual(state.appError?.userMessage, error.userMessage)
    }

    func testChangingPDFResetsSharedPageAndTranslation() {
        let state = LibraryViewState()
        let first = PDFFile(URL(fileURLWithPath: "/tmp/first.pdf"))
        state.selectedPDFFile = first
        state.currentPageIndex = 3
        let request = state.beginTranslation(first, .japanese)
        XCTAssertEqual(request.pageIndex, 3)

        state.selectedPDFFile = PDFFile(URL(fileURLWithPath: "/tmp/second.pdf"))

        XCTAssertEqual(state.currentPageIndex, 0)
        XCTAssertNil(state.translationRequest)
        XCTAssertFalse(state.isTranslating)
    }

    func testCompletionFromClosedPDFCannotAppearOnAnotherPDF() {
        let state = LibraryViewState()
        let first = PDFFile(URL(fileURLWithPath: "/tmp/first.pdf"))
        state.selectedPDFFile = first
        let request = state.beginTranslation(first, .japanese)

        state.selectedPDFFile = nil
        state.selectedPDFFile = PDFFile(URL(fileURLWithPath: "/tmp/second.pdf"))
        state.prepareTranslation("Old source", for: request)
        state.completeTranslation("Old result", for: request)

        XCTAssertNil(state.translationRequest)
        XCTAssertTrue(state.translatedText.isEmpty)
        XCTAssertFalse(state.isTranslationPresented)
    }

    func testOldRequestCannotFinishNewTranslationOfSamePDF() {
        let state = LibraryViewState()
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/document.pdf"))
        state.selectedPDFFile = pdfFile
        let old = state.beginTranslation(pdfFile, .japanese)
        let current = state.beginTranslation(pdfFile, .english)

        state.finishTranslation(old)
        state.completeTranslation("Old result", for: old)
        XCTAssertTrue(state.isTranslating)
        XCTAssertEqual(state.translationRequest?.id, current.id)

        state.completeTranslation("Current result", for: current)
        XCTAssertEqual(state.translatedText, "Current result")
        XCTAssertTrue(state.isTranslationPresented)
        XCTAssertFalse(state.isTranslating)
    }
}
