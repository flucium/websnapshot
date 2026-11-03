import Foundation
import Combine
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryTranslationStateTests: XCTestCase {
    func testLibraryViewStatePublishesChanges() {
        let state = LibraryViewState()
        var changed = false
        let observation = state.objectWillChange.sink {
            changed = true
        }
        defer { observation.cancel() }

        state.currentPageIndex = 3
        XCTAssertTrue(changed)
        XCTAssertEqual(state.currentPageIndex, 3)

        changed = false
        state.searchText = "Article"
        XCTAssertTrue(changed)

        let error = AppError.error("The PDF could not be opened.")
        LibraryPDFView.Coordinator(state).present(error)
        XCTAssertEqual(state.errorTitle, "PDF Could Not Be Opened")
        XCTAssertEqual(state.appError?.userMessage, error.userMessage)
    }

    func testChangingPDFResetsPageAndTranslation() {
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

    func testSlowerOpenCannotReplaceTheLatestPDF() {
        let state = LibraryViewState()
        let first = PDFFile(URL(fileURLWithPath: "/tmp/first.pdf"))
        let second = PDFFile(URL(fileURLWithPath: "/tmp/second.pdf"))
        let older = state.beginOpeningPDF()
        let newer = state.beginOpeningPDF()

        state.completeOpeningPDF(second, for: newer)
        state.completeOpeningPDF(first, for: older)

        XCTAssertTrue(state.selectedPDFFile === second)
        XCTAssertEqual(state.selectedPDFRowID, second.persistentModelID)
    }

    func testClosingPDFInvalidatesPendingOpen() {
        let state = LibraryViewState()
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/pending.pdf"))
        let request = state.beginOpeningPDF()
        state.downloadingPDFs.insert(pdfFile.persistentModelID)

        LibraryViewService.closeDisplayedPDF(state)
        state.completeOpeningPDF(pdfFile, for: request)

        XCTAssertNil(state.selectedPDFFile)
        XCTAssertTrue(state.downloadingPDFs.isEmpty)
    }

    func testTranslationUsesDisplayedSnapshotUntilPDFRefreshes() async throws {
        let fixture = try ContentSearchFixture(["Original displayed text"])
        defer { fixture.remove() }
        let state = LibraryViewState()
        let pdfFile = PDFFile(fixture.url)
        let container = try ModelContainer(for: PDFFile.self, PDFTag.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.insert(pdfFile)
        try container.mainContext.save()
        state.selectedPDFFile = pdfFile
        LibraryViewService.refreshDisplayedPDF(state)
        let request = state.beginTranslation(pdfFile, .japanese)
        let data = try XCTUnwrap(request.data)

        try ContentSearchFixture.data(["Replacement text"]).write(to: fixture.url, options: .atomic)
        let extracted = try await PDFContentService().text(data, pageIndex: request.pageIndex)

        XCTAssertTrue(extracted.contains("Original displayed text"))
        XCTAssertEqual(state.displayedPDFVersion, request.version)

        LibraryViewService.refreshDisplayedPDF(state)
        state.completeTranslation("Outdated result", for: request)

        XCTAssertNotEqual(state.displayedPDFVersion, request.version)
        XCTAssertNil(state.translationRequest)
        XCTAssertFalse(state.isTranslationPresented)
        XCTAssertTrue(state.translatedText.isEmpty)
        let updated = try XCTUnwrap(state.displayedPDFData)
        let currentText = try await PDFContentService().text(updated, pageIndex: 0)
        XCTAssertTrue(currentText.contains("Replacement text"))
    }

    func testUnchangedPDFDoesNotInvalidateCurrentTranslation() throws {
        let fixture = try ContentSearchFixture(["Unchanged content"])
        defer { fixture.remove() }
        let state = LibraryViewState()
        let pdfFile = PDFFile(fixture.url)
        let container = try ModelContainer(for: PDFFile.self, PDFTag.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        container.mainContext.insert(pdfFile)
        try container.mainContext.save()
        state.selectedPDFFile = pdfFile
        LibraryViewService.refreshDisplayedPDF(state)
        let request = state.beginTranslation(pdfFile, .japanese)

        LibraryViewService.refreshDisplayedPDF(state)

        XCTAssertTrue(state.isCurrentTranslation(request))
        XCTAssertEqual(state.displayedPDFVersion, request.version)
    }
}
