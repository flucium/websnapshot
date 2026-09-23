import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

private enum ExpectedFailure: Error {
    case fileDeletion
}

final class LibraryViewServiceTests: XCTestCase {
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
}
