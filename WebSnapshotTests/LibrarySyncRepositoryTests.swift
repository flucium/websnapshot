import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibrarySyncRepositoryTests: XCTestCase {
    func testSyncedPDFsShareNormalizedTags() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let first = record(["  Café  Notes ", "cafe notes", "", "資料"])
        let second = record(["ＣＡＦＥ ＮＯＴＥＳ"])

        try LibrarySyncRepository.apply(SyncIndex(files: [first, second]), context, root)
        try context.save()

        let files = try context.fetch(FetchDescriptor<PDFFile>())
        let firstPDF = try XCTUnwrap(files.first { $0.libraryID == first.id })
        let secondPDF = try XCTUnwrap(files.first { $0.libraryID == second.id })
        let sharedTag = try XCTUnwrap(firstPDF.tags.first { $0.normalizedName == "cafe notes" })

        XCTAssertEqual(Set(firstPDF.tags.map(\.name)), ["Café Notes", "資料"])
        XCTAssertEqual(secondPDF.tags.count, 1)
        XCTAssertTrue(secondPDF.tags.first === sharedTag)
        XCTAssertEqual(sharedTag.pdfFiles.count, 2)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 2)
    }

    func testTagReassignmentPreservesSharedTagAndRemovesUnusedTags() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var first = record(["Research"])
        var second = record(["Temporary"])

        try LibrarySyncRepository.apply(SyncIndex(files: [first, second]), context, root)
        try context.save()

        let sharedTag = try XCTUnwrap(context.fetch(FetchDescriptor<PDFTag>()).first { $0.name == "Research" })
        first.tags = SyncPDFTags([], try XCTUnwrap(first.tags?.stamp))
        second.tags = SyncPDFTags(["research"], try XCTUnwrap(second.tags?.stamp))

        try LibrarySyncRepository.apply(SyncIndex(files: [first, second]), context, root)
        try context.save()

        let files = try context.fetch(FetchDescriptor<PDFFile>())
        let firstPDF = try XCTUnwrap(files.first { $0.libraryID == first.id })
        let secondPDF = try XCTUnwrap(files.first { $0.libraryID == second.id })

        XCTAssertTrue(firstPDF.tags.isEmpty)
        XCTAssertEqual(secondPDF.tags.count, 1)
        XCTAssertTrue(secondPDF.tags.first === sharedTag)
        XCTAssertEqual(sharedTag.pdfFiles.count, 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
    }

    func testDeletedPDFDoesNotPreventAnotherPDFFromUsingItsTag() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        var first = record(["Research"])

        try LibrarySyncRepository.apply(SyncIndex(files: [first]), context, root)
        try context.save()

        first.deleted = try XCTUnwrap(first.location?.stamp)
        let second = record(["research"])

        try LibrarySyncRepository.apply(SyncIndex(files: [first, second]), context, root)
        try context.save()

        let files = try context.fetch(FetchDescriptor<PDFFile>())
        let tags = try context.fetch(FetchDescriptor<PDFTag>())

        XCTAssertEqual(files.count, 1)
        XCTAssertEqual(files.first?.libraryID, second.id)
        XCTAssertEqual(files.first?.tags.map(\.normalizedName), ["research"])
        XCTAssertEqual(tags.count, 1)
        XCTAssertEqual(tags.first?.pdfFiles.count, 1)
    }

    private func record(_ names: [String]) -> SyncPDFRecord {
        let id = UUID()
        let stamp = SyncStamp(counter: 1, deviceID: UUID(), operationID: UUID())

        return SyncPDFRecord(id: id,
                             location: SyncPDFLocation(relativePath: "PDFs/\(id.uuidString).pdf", contentHash: "fixture", stamp: stamp),
                             tags: SyncPDFTags(names, stamp))
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(for: PDFFile.self, PDFTag.self,
                                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
        container.mainContext.autosaveEnabled = false
        return container
    }
}
