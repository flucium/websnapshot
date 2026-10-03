import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

private enum ExpectedFailure: Error {
    case fileDeletion
}

final class LibraryViewServiceTests: XCTestCase {
    @MainActor
    func testImportCopiesPDFAndUsesUniqueNamesWithoutChangingSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let importDirectory = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Report.pdf")
        let pdfData = try makePDFData()
        try pdfData.write(to: source)
        let container = try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let first = try LibraryViewService.importPDF(source, importDirectory, context)
        let second = try LibraryViewService.importPDF(source, importDirectory, context)

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.lastPathComponent, "Report.pdf")
        XCTAssertEqual(second.lastPathComponent, "Report 2.pdf")
        XCTAssertEqual(try Data(contentsOf: source), pdfData)
        XCTAssertEqual(try Data(contentsOf: first), pdfData)
        XCTAssertEqual(try Data(contentsOf: second), pdfData)
        let importedPDFs = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(importedPDFs.count, 2)
        XCTAssertTrue(importedPDFs.allSatisfy { $0.addedAt != nil })
    }

    @MainActor
    func testImportRejectsInvalidPDFWithoutRegisteringIt() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Invalid.pdf")
        try Data("not a PDF".utf8).write(to: source)
        let container = try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )

        XCTAssertThrowsError(try LibraryViewService.importPDF(source, directory, container.mainContext))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("Invalid 2.pdf").path))
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 0)
    }

    @MainActor
    func testExportReplacesChosenCopyAndPreservesSource() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Source.pdf")
        let destination = directory.appendingPathComponent("Export.pdf")
        let pdfData = try makePDFData()
        try pdfData.write(to: source)
        try Data("old copy".utf8).write(to: destination)

        try LibraryViewService.exportPDF(source, destination)

        XCTAssertEqual(try Data(contentsOf: source), pdfData)
        XCTAssertEqual(try Data(contentsOf: destination), pdfData)
        XCTAssertThrowsError(try LibraryViewService.exportPDF(source, source))
        XCTAssertEqual(try Data(contentsOf: source), pdfData)
    }

    @MainActor
    func testFileDeletionFailureKeepsLibraryEntry() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            configurations: configuration
        )
        let context = container.mainContext
        let url = URL(fileURLWithPath: "/tmp/example.pdf")

        context.insert(PDFFile(url))
        try context.save()

        XCTAssertThrowsError(
            try LibraryViewService.delete(
                context,
                url,
                url,
                { _ in
                    throw ExpectedFailure.fileDeletion
                }
            )
        )

        let entries = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.url, url)
    }

    @MainActor
    func testSearchModesMatchTitleAndTags() {
        let pdfFile = PDFFile(URL(fileURLWithPath: "/tmp/Quarterly Report.pdf"))
        pdfFile.tags = [
            PDFTag("Research", normalizedName: "research")
        ]

        XCTAssertTrue(
            LibraryViewService.matches(
                pdfFile,
                "quarterly",
                .title
            )
        )
        XCTAssertFalse(
            LibraryViewService.matches(
                pdfFile,
                "research",
                .title
            )
        )
        XCTAssertTrue(
            LibraryViewService.matches(
                pdfFile,
                "RESEARCH",
                .tag
            )
        )
        XCTAssertFalse(
            LibraryViewService.matches(
                pdfFile,
                "quarterly",
                .tag
            )
        )
        XCTAssertTrue(
            LibraryViewService.matches(
                pdfFile,
                "research",
                .all
            )
        )
        XCTAssertTrue(
            LibraryViewService.matches(
                pdfFile,
                "  ",
                .tag
            )
        )
    }

    @MainActor
    func testMissingPDFRemovesItsUnusedTags() throws {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            configurations: configuration
        )
        let context = container.mainContext
        let pdfFile = PDFFile(
            URL(fileURLWithPath: "/tmp/websnapshot-missing-tagged-file.pdf")
        )

        context.insert(pdfFile)
        try context.save()
        try PDFTagService.replaceTags(["Missing"], for: pdfFile, in: context)

        try LibraryViewService.deleteMissingFiles(context, [pdfFile])

        XCTAssertTrue(try context.fetch(FetchDescriptor<PDFFile>()).isEmpty)
        XCTAssertTrue(try context.fetch(FetchDescriptor<PDFTag>()).isEmpty)
    }

    private func makePDFData() throws -> Data {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return data as Data
    }
}
