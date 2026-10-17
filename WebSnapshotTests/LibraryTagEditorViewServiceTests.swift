import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryTagEditorViewServiceTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testTagChangesRemainDraftUntilSaved() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/Article.pdf"))
        context.insert(pdfFile)
        try PDFTagService.replaceTags(["Original"], pdfFile, context, sync: sync)
        let state = LibraryViewState()
        state.presentTagEditor(pdfFile)
        let editor = state.libraryTagEditorViewState

        editor.newTagName = "  Research  "
        LibraryTagEditorViewService.addNewTag(editor)
        editor.newTagName = "research"
        LibraryTagEditorViewService.addNewTag(editor)
        LibraryTagEditorViewService.removeTag(editor, "ORIGINAL")

        XCTAssertEqual(editor.tagNames, ["Research"])
        XCTAssertTrue(editor.newTagName.isEmpty)
        XCTAssertEqual(PDFTagService.tagNames(pdfFile.tags), ["Original"])

        XCTAssertTrue(LibraryTagEditorViewService.save(editor, pdfFile, context, sync: sync))
        XCTAssertEqual(PDFTagService.tagNames(pdfFile.tags), ["Research"])
        XCTAssertEqual(state.tagEditorPDFFile?.persistentModelID, pdfFile.persistentModelID)

        let savedContext = ModelContext(container)
        let savedPDF = try XCTUnwrap(savedContext.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(PDFTagService.tagNames(savedPDF.tags), ["Research"])

        state.closeTagEditor()
        XCTAssertNil(state.tagEditorPDFFile)
        XCTAssertTrue(editor.tagNames.isEmpty)
    }

    func testClosingAndReopeningTagEditorRestoresSavedTags() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/Article.pdf"))
        context.insert(pdfFile)
        try PDFTagService.replaceTags(["Original"], pdfFile, context, sync: sync)
        let state = LibraryViewState()
        state.presentTagEditor(pdfFile)
        let editor = state.libraryTagEditorViewState
        editor.tagNames = ["Draft"]
        editor.newTagName = "Unfinished"
        editor.appError = .error("Previous error")

        state.closeTagEditor()

        XCTAssertNil(state.tagEditorPDFFile)
        XCTAssertTrue(editor.tagNames.isEmpty)
        XCTAssertTrue(editor.newTagName.isEmpty)
        XCTAssertNil(editor.appError)
        XCTAssertEqual(PDFTagService.tagNames(pdfFile.tags), ["Original"])

        state.presentTagEditor(pdfFile)

        XCTAssertEqual(editor.tagNames, ["Original"])
        XCTAssertTrue(editor.newTagName.isEmpty)
        XCTAssertNil(editor.appError)
    }

    func testFailedSaveKeepsEditorOpenAndPreservesDraft() throws {
        let container = try makeContainer()
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/Unregistered.pdf"))
        let state = LibraryViewState()
        state.presentTagEditor(pdfFile)
        let editor = state.libraryTagEditorViewState
        editor.tagNames = ["Draft"]
        editor.newTagName = "Unfinished"

        XCTAssertFalse(LibraryTagEditorViewService.save(editor, pdfFile, container.mainContext, sync: sync))

        XCTAssertEqual(state.tagEditorPDFFile?.persistentModelID, pdfFile.persistentModelID)
        XCTAssertEqual(editor.tagNames, ["Draft"])
        XCTAssertEqual(editor.newTagName, "Unfinished")
        XCTAssertNotNil(editor.appError)
        XCTAssertNil(state.appError)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: PDFFile.self, PDFTag.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
