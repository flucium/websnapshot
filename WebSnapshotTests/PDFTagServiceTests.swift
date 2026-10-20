import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

final class PDFTagServiceTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testDraftTagOperationsNormalizeSortAndToggleNames() {
        var tagNames = PDFTagService.addingTag(
            "  Work  Notes ",
            ["資料"]
        )

        XCTAssertEqual(Set(tagNames), ["Work Notes", "資料"])

        tagNames = PDFTagService.addingTag("work notes", tagNames)
        XCTAssertEqual(tagNames.count, 2)
        XCTAssertTrue(PDFTagService.containsTag("WORK NOTES", tagNames))

        tagNames = PDFTagService.togglingTag("Work Notes", tagNames)
        XCTAssertEqual(tagNames, ["資料"])

        tagNames = PDFTagService.togglingTag("Research", tagNames)
        XCTAssertEqual(Set(tagNames), ["Research", "資料"])

        tagNames = PDFTagService.removingTag("research", tagNames)
        XCTAssertEqual(tagNames, ["資料"])
    }

    @MainActor
    func testReplaceTagsNormalizesAndDeduplicatesNames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/example.pdf"))

        context.insert(pdfFile)
        try context.save()

        try LibraryService.replaceTags(
            ["  Work  Notes ", "work notes", "資料"],
            pdfFile,
            context, sync: sync
        )

        XCTAssertEqual(pdfFile.tags.count, 2)
        XCTAssertEqual(Set(pdfFile.tags.map(\.name)), ["Work Notes", "資料"])

        let storedTags = try context.fetch(FetchDescriptor<PDFTag>())
        XCTAssertEqual(storedTags.count, 2)
    }

    @MainActor
    func testSharedTagIsReusedAndRemovedAfterItsLastAssignment() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let firstPDFFile = PDFFile(URL(fileURLWithPath: "/tmp/first.pdf"))
        let secondPDFFile = PDFFile(URL(fileURLWithPath: "/tmp/second.pdf"))

        context.insert(firstPDFFile)
        context.insert(secondPDFFile)
        try context.save()

        try LibraryService.replaceTags(["Research"], firstPDFFile, context, sync: sync)
        try LibraryService.replaceTags(["research"], secondPDFFile, context, sync: sync)

        var storedTags = try context.fetch(FetchDescriptor<PDFTag>())
        XCTAssertEqual(storedTags.count, 1)
        XCTAssertEqual(storedTags.first?.pdfFiles.count, 2)

        try LibraryService.replaceTags([], firstPDFFile, context, sync: sync)

        storedTags = try context.fetch(FetchDescriptor<PDFTag>())
        XCTAssertEqual(storedTags.count, 1)
        XCTAssertEqual(storedTags.first?.pdfFiles.count, 1)
        XCTAssertTrue(storedTags.first?.pdfFiles.first === secondPDFFile)

        try LibraryService.replaceTags([], secondPDFFile, context, sync: sync)

        storedTags = try context.fetch(FetchDescriptor<PDFTag>())
        XCTAssertTrue(storedTags.isEmpty)
    }

    @MainActor
    func testDeletingPDFRemovesItsUnusedTags() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let url = URL(fileURLWithPath: "/tmp/example.pdf")
        let pdfFile = PDFFile(url)

        context.insert(pdfFile)
        try context.save()
        try LibraryService.replaceTags(["Temporary"], pdfFile, context, sync: sync)

        try LibraryService.removePDFRecords(context, url, sync: sync)

        XCTAssertTrue(try context.fetch(FetchDescriptor<PDFFile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PDFTag>()).isEmpty)
    }

    @MainActor
    private func makeContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)

        return try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            configurations: configuration
        )
    }
}
