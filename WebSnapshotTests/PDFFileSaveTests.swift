import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class PDFFileSaveTests: XCTestCase {
    func testReusingOriginalPathPreservesRenamedPDFAndItsTags() throws {
        try assertReusedPathPreservesRenamedPDF(fixedStorage: true)
    }

    func testManualSaveToOriginalPathPreservesRenamedPDFAndItsTags() throws {
        try assertReusedPathPreservesRenamedPDF(fixedStorage: false)
    }

    private func assertReusedPathPreservesRenamedPDF(fixedStorage: Bool) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("A.pdf")
        let renamed = directory.appendingPathComponent("B.pdf")
        try Data("original".utf8).write(to: original)
        let container = try makeContainer()
        let context = container.mainContext
        try PDFFileService.save(context, original)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let entryID = entry.persistentModelID
        try PDFTagService.replaceTags(["Original"], for: entry, in: context)
        try FileManager.default.moveItem(at: original, to: renamed)
        try StorageSettingsService.saveFixedStorage(context, directory)
        let settings = try context.fetch(FetchDescriptor<StorageSettings>())
        let document = PDFFileDocument(Data("new".utf8))
        let savedURL: URL?
        if fixedStorage {
            savedURL = try WebCaptureService.save(document, "A", nil, context, settings)
        } else {
            savedURL = try WebCaptureService.save(document, "A", nil, context, []) { _, _, document in
                try XCTUnwrap(document).data.write(to: original, options: .atomic)
                return original
            }
        }
        XCTAssertEqual(savedURL?.standardizedFileURL, original.standardizedFileURL)

        let entries = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entry.persistentModelID, entryID)
        XCTAssertEqual(entry.resolvedURL.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(entry.url.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(entry.tags.map(\.name), ["Original"])
        let newEntry = try XCTUnwrap(entries.first { $0.persistentModelID != entryID })
        XCTAssertEqual(newEntry.resolvedURL.standardizedFileURL, original.standardizedFileURL)
        XCTAssertTrue(newEntry.tags.isEmpty)

        // Deleting the new record must not also delete the renamed record.
        try PDFFileService.delete(context, newEntry.url)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
        XCTAssertEqual(try Data(contentsOf: renamed), Data("original".utf8))
    }

    func testRegisteringRenamedPathReusesExistingEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("A.pdf")
        let renamed = directory.appendingPathComponent("B.pdf")
        try Data("original".utf8).write(to: original)
        let container = try makeContainer()
        let context = container.mainContext
        try PDFFileService.save(context, original)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try PDFTagService.replaceTags(["Keep"], for: entry, in: context)
        try FileManager.default.moveItem(at: original, to: renamed)

        try PDFFileService.save(context, renamed)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(entry.url.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(entry.tags.map(\.name), ["Keep"])
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: PDFFile.self, PDFTag.self, StorageSettings.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
