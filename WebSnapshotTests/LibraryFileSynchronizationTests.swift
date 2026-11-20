import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryFileSynchronizationTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testMaintenanceWithoutFileChangesDoesNotCommitUnrelatedEdits() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Article.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        context.autosaveEnabled = false
        try LibraryService.registerPDF(context, url, sync)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let originalDate = pdf.addedAt
        pdf.addedAt = Date(timeIntervalSince1970: 1)

        try LibraryService.refreshLocations(context, sync)
        try LibraryService.deleteMissingFiles(context, [pdf], sync)
        try LibraryService.removePDFRecords(context, directory.appendingPathComponent("Other.pdf"), sync)

        XCTAssertTrue(context.hasChanges)
        let persisted = try XCTUnwrap(ModelContext(container).fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(persisted.addedAt, originalDate)
    }

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
        try LibraryService.replaceTags(["Keep"], entry, context, sync)

        XCTAssertEqual(entry.availability, .unavailable)
        try LibraryService.deleteMissingFiles(context, [entry], sync)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)

        try LibraryService.deleteMissingFiles(context, [entry], sync, [entry.persistentModelID])
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
        try LibraryService.registerPDF(context, original, sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Keep"], entry, context, sync)
        try FileManager.default.moveItem(at: original, to: renamed)

        XCTAssertEqual(try entry.resolveURL().standardizedFileURL, renamed.standardizedFileURL)
        try LibraryService.deleteMissingFiles(context, [entry], sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
        XCTAssertTrue(LibrarySearch.matches(entry, "renamed", .title))
    }

    func testUnresolvableBookmarkKeepsEntryAndTags() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(
            FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString),
            Data([0, 1])
        )
        context.insert(entry)
        try LibraryService.replaceTags(["Keep"], entry, context, sync)

        try LibraryService.deleteMissingFiles(context, [entry], sync)

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
        try LibraryService.registerPDF(context, url, sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Temporary"], entry, context, sync)

        try FileManager.default.removeItem(at: url)
        try LibraryService.deleteMissingFiles(context, [entry], sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0)
    }

    func testPDFMovedToICloudTrashRemovesEntryAndPreservesTheFile() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let trash = directory.appendingPathComponent("Mobile Documents/.Trash", isDirectory: true)
        try FileManager.default.createDirectory(at: trash, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Article.pdf")
        try Data("fixture".utf8).write(to: url)
        let container = try makeContainer()
        let context = container.mainContext
        try LibraryService.registerPDF(context, url, sync)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        try LibraryService.replaceTags(["Temporary"], entry, context, sync)

        let destination = trash.appendingPathComponent(url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: destination)
        try LibraryService.deleteMissingFiles(context, [entry], sync)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 0)
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
        try LibraryService.replaceTags(["Temporary"], entry, context, sync)
        let monitor = LibraryPDFFileMonitor()
        defer { monitor.stop() }
        let deleted = expectation(description: "The file monitor reports the external deletion")
        let onMissing: (LibraryPDFFileMonitor.Change) -> Void = { [sync] change in
            guard change.wasDeleted else { return }
            do {
                try LibraryService.deleteMissingFiles(
                    context, [entry], sync, [change.fileID]
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
        try LibraryService.replaceTags(["Keep"], entry, context, sync)

        try LibraryService.deleteMissingFiles(
            context, [entry], sync, [entry.persistentModelID]
        )

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFTag>()), 1)
    }

    func testMonitorReportsContentChangesWithoutDeletion() async throws {
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
        let modified = expectation(description: "Content changes are reported")
        var reported = false
        monitor.sync([entry]) { change in
            guard change.wasModified, !reported else { return }
            reported = true
            XCTAssertFalse(change.wasDeleted)
            XCTAssertEqual(change.fileID, entry.persistentModelID)
            modified.fulfill()
        }

        try Data("updated content".utf8).write(to: url)

        await fulfillment(of: [modified], timeout: 3)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 1)
    }

    func testMissingParentIsUnavailableRatherThanDeleted() {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("document.pdf")
        XCTAssertEqual(FileIO.availability(url), .unavailable)
    }

    func testDisplayLocationsFollowRenamesAndRemoveDeletedEntries() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Original.pdf")
        let renamed = directory.appendingPathComponent("Renamed.pdf")
        try Data("fixture".utf8).write(to: original)
        let container = try makeContainer()
        let context = container.mainContext
        try LibraryService.registerPDF(context, original, sync)
        let pdf = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let id = pdf.persistentModelID
        let state = LibraryViewState()
        let monitor = LibraryPDFFileMonitor()
        defer { monitor.stop() }

        LibraryViewService.synchronizeLibraryFiles(state, context, monitor, sync)
        XCTAssertEqual(state.fileURL(pdf).standardizedFileURL, original.standardizedFileURL)
        XCTAssertEqual(state.fileAvailability(pdf), .available)

        try FileManager.default.moveItem(at: original, to: renamed)
        LibraryViewService.synchronizeLibraryFiles(state, context, monitor, sync)
        XCTAssertEqual(state.fileURL(pdf).standardizedFileURL, renamed.standardizedFileURL)
        XCTAssertTrue(LibrarySearch.matches(pdf, "Renamed", .title, title: state.fileURL(pdf).lastPathComponent))

        try FileManager.default.removeItem(at: renamed)
        LibraryViewService.synchronizeLibraryFiles(state, context, monitor, sync)
        XCTAssertNil(state.fileLocations[id])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: PDFFile.self, PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
