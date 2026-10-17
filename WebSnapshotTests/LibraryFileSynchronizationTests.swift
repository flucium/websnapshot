import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryFileSynchronizationTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testUndownloadedPDFKeepsItsEntryAndTagsAfterDeletionEvent() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Article.pdf")
        let placeholder = directory.appendingPathComponent(".Article.pdf.icloud")
        let data = Data("placeholder".utf8)
        try data.write(to: placeholder)
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(url)
        context.insert(entry)
        try PDFTagService.replaceTags(["Keep"], entry, context, sync: sync)

        XCTAssertEqual(entry.availability, .unavailable)
        try PDFFileService.deleteMissingFiles(context, [entry], sync: sync)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)

        try PDFFileService.deleteMissingFiles(context, [entry], sync: sync, [entry.persistentModelID])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
        XCTAssertEqual(entry.tags.map(\.name), ["Keep"])
        XCTAssertEqual(try Data(contentsOf: placeholder), data)
    }

    func testRenamedPDFKeepsItsEntryAndTags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("original.pdf")
        let renamed = directory.appendingPathComponent("renamed.pdf")
        try Data("fixture".utf8).write(to: original)

        let container = try makeContainer()
        let context = container.mainContext
        try PDFFileService.save(context, original, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try PDFTagService.replaceTags(["Keep"], entry, context, sync: sync)
        try FileManager.default.moveItem(at: original, to: renamed)

        XCTAssertEqual(try entry.resolveURL().standardizedFileURL, renamed.standardizedFileURL)
        try PDFFileService.deleteMissingFiles(context, [entry], sync: sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
        XCTAssertTrue(LibraryService.matches(entry, "renamed", .title))
    }

    func testUnresolvableBookmarkKeepsEntryAndTags() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            Data([0, 1])
        )
        context.insert(entry)
        try PDFTagService.replaceTags(["Keep"], entry, context, sync: sync)

        try PDFFileService.deleteMissingFiles(context, [entry], sync: sync)

        XCTAssertEqual(entry.availability, .unavailable)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
    }

    func testExternallyDeletedBookmarkedPDFRemovesEntryAndTags() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        try PDFFileService.save(context, url, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try PDFTagService.replaceTags(["Temporary"], entry, context, sync: sync)

        try FileManager.default.removeItem(at: url)
        try PDFFileService.deleteMissingFiles(context, [entry], sync: sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0)
    }

    func testTrashedBookmarkedPDFRemovesEntryWithoutDeletingTrashedFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var trashedURL: NSURL?
        defer {
            if let trashedURL { try? FileManager.default.removeItem(at: trashedURL as URL) }
            try? FileManager.default.removeItem(at: directory)
        }
        let url = directory.appendingPathComponent("websnapshot-fixture-\(UUID().uuidString).pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        try PDFFileService.save(context, url, sync: sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try PDFTagService.replaceTags(["Temporary"], entry, context, sync: sync)

        try FileManager.default.trashItem(at: url, resultingItemURL: &trashedURL)
        try PDFFileService.deleteMissingFiles(context, [entry], sync: sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0)
        let destination = try XCTUnwrap(trashedURL) as URL
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    }

    func testDeleteEventRemovesEntryEvenAfterBookmarkBecomesUnavailable() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(url)
        context.insert(entry)
        try PDFTagService.replaceTags(["Temporary"], entry, context, sync: sync)
        let monitor = LibraryPDFFileMonitor()
        defer { monitor.stop() }
        let deleted = expectation(description: "The file monitor reports the external deletion")
        let onMissing: (LibraryPDFFileMonitor.Change) -> Void = { [sync] change in
            guard change.wasDeleted else { return }
            do {
                try PDFFileService.deleteMissingFiles(
                    context, [entry], sync: sync, [change.fileID]
                )
            } catch {
                XCTFail("Synchronization failed: \(error)")
            }
            deleted.fulfill()
        }
        monitor.sync([entry], onMissing)

        try FileManager.default.removeItem(at: url)
        entry.bookmarkData = Data([0, 1])
        monitor.sync([entry], onMissing)
        await fulfillment(of: [deleted], timeout: 3)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0)
    }

    func testMonitorDetectsDeletionAfterAtomicReplacement() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        try Data("original".utf8).write(to: url)
        let container = try makeContainer()
        let entry = PDFFile(url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let monitor = LibraryPDFFileMonitor()
        defer { monitor.stop() }
        let deleted = expectation(description: "The replacement file is still monitored")
        monitor.sync([entry]) { change in
            if change.wasDeleted {
                deleted.fulfill()
            }
        }

        try Data("replacement".utf8).write(to: url, options: .atomic)
        try await Task.sleep(for: .milliseconds(200))
        try FileManager.default.removeItem(at: url)

        await fulfillment(of: [deleted], timeout: 3)
    }

    func testDeleteEventDoesNotRemoveAReplacementAtTheSamePath() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("document.pdf")
        try Data("replacement".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(url)
        context.insert(entry)
        try PDFTagService.replaceTags(["Keep"], entry, context, sync: sync)

        try PDFFileService.deleteMissingFiles(
            context, [entry], sync: sync, [entry.persistentModelID]
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
    }

    func testMissingParentIsUnavailableRatherThanDeleted() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("document.pdf")
        XCTAssertEqual(FileIO.availability(url), .unavailable)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PDFFile.self, PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
