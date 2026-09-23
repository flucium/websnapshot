import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

final class PDFTagServiceTests: XCTestCase {
    func testDraftTagOperationsNormalizeSortAndToggleNames() {
        var tagNames = PDFTagService.addingTag(
            "  Work  Notes ",
            to: ["資料"]
        )

        XCTAssertEqual(Set(tagNames), ["Work Notes", "資料"])

        tagNames = PDFTagService.addingTag("work notes", to: tagNames)
        XCTAssertEqual(tagNames.count, 2)
        XCTAssertTrue(PDFTagService.containsTag("WORK NOTES", in: tagNames))

        tagNames = PDFTagService.togglingTag("Work Notes", in: tagNames)
        XCTAssertEqual(tagNames, ["資料"])

        tagNames = PDFTagService.togglingTag("Research", in: tagNames)
        XCTAssertEqual(Set(tagNames), ["Research", "資料"])

        tagNames = PDFTagService.removingTag("research", from: tagNames)
        XCTAssertEqual(tagNames, ["資料"])
    }

    @MainActor
    func testReplaceTagsNormalizesAndDeduplicatesNames() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/example.pdf"))

        context.insert(pdfFile)
        try context.save()

        try PDFTagService.replaceTags(
            ["  Work  Notes ", "work notes", "資料"],
            for: pdfFile,
            in: context
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

        try PDFTagService.replaceTags(["Research"], for: firstPDFFile, in: context)
        try PDFTagService.replaceTags(["research"], for: secondPDFFile, in: context)

        var storedTags = try context.fetch(FetchDescriptor<PDFTag>())
        XCTAssertEqual(storedTags.count, 1)
        XCTAssertEqual(storedTags.first?.pdfFiles.count, 2)

        try PDFTagService.replaceTags([], for: firstPDFFile, in: context)

        storedTags = try context.fetch(FetchDescriptor<PDFTag>())
        XCTAssertEqual(storedTags.count, 1)
        XCTAssertEqual(storedTags.first?.pdfFiles.count, 1)
        XCTAssertTrue(storedTags.first?.pdfFiles.first === secondPDFFile)

        try PDFTagService.replaceTags([], for: secondPDFFile, in: context)

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
        try PDFTagService.replaceTags(["Temporary"], for: pdfFile, in: context)

        try PDFFileService.delete(context, url)

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
