import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class PDFFileSaveTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testNewRegistrationRecordsDateWithoutResettingItOnSave() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("New.pdf")
        try Data("pdf".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext

        let beforeSave = Date()
        try LibraryService.registerPDF(context, url, sync: sync)
        let afterSave = Date()

        let pdfFile = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let addedAt = try XCTUnwrap(pdfFile.addedAt)
        XCTAssertGreaterThanOrEqual(addedAt, beforeSave)
        XCTAssertLessThanOrEqual(addedAt, afterSave)

        try LibraryService.registerPDF(context, url, sync: sync)
        XCTAssertEqual(pdfFile.addedAt, addedAt)
    }

    func testExistingRegistrationWithoutDateStaysUnknown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("Existing.pdf")
        try Data("pdf".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        let pdfFile = PDFFile(url)
        context.insert(pdfFile)
        try context.save()

        try LibraryService.registerPDF(context, url, sync: sync)

        XCTAssertNil(pdfFile.addedAt)
    }

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
        try LibraryService.registerPDF(context, original, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let entryID = entry.persistentModelID
        try LibraryService.replaceTags(["Original"], entry, context, sync: sync)
        try FileManager.default.moveItem(at: original, to: renamed)
        try StorageSettingsService.saveFixedStorage(context, directory, sync: sync)
        let settings = try context.fetch(FetchDescriptor<StorageSettings>())
        let document = PDFFileDocument(Data("new".utf8))
        let savedURL: URL?
        if fixedStorage {
            savedURL = try LibraryService.savePDF(document.data, URL.pdfFileName("A", nil), context, settings, sync: sync)
        } else {
            savedURL = try LibraryService.savePDF(document.data, URL.pdfFileName("A", nil), context, [], sync: sync) { _ in
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
        try LibraryService.removePDFRecords(context, newEntry.url, sync: sync)
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
        try LibraryService.registerPDF(context, original, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Keep"], entry, context, sync: sync)
        try FileManager.default.moveItem(at: original, to: renamed)

        try LibraryService.registerPDF(context, renamed, sync: sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(entry.url.standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertEqual(entry.tags.map(\.name), ["Keep"])
    }

    func testRegisteringThroughDirectorySymlinkReusesExistingEntry() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = directory.appendingPathComponent("Storage", isDirectory: true)
        let alias = directory.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: storage)
        let url = storage.appendingPathComponent("Document.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        try LibraryService.registerPDF(context, url, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let addedAt = entry.addedAt
        try LibraryService.replaceTags(["Keep"], entry, context, sync: sync)

        try LibraryService.registerPDF(context, alias.appendingPathComponent("Document.pdf"), sync: sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(entry.tags.map(\.name), ["Keep"])
        XCTAssertEqual(entry.addedAt, addedAt)
    }

    func testDeletingThroughDirectorySymlinkRemovesEntryAndUnusedTags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = directory.appendingPathComponent("Storage", isDirectory: true)
        let alias = directory.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: storage)
        let url = storage.appendingPathComponent("Document.pdf")
        let aliasedURL = alias.appendingPathComponent("Document.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        try LibraryService.registerPDF(context, url, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Temporary"], entry, context, sync: sync)

        try LibraryService.delete(context, aliasedURL, aliasedURL, sync: sync)

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: PDFFile.self, PDFTag.self, StorageSettings.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }
}
