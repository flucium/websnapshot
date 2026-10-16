import CoreGraphics
import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class WebCaptureServiceTests: XCTestCase {
    func testFixedStorageSavesAndRegistersWithoutOpeningPanelOrOverwriting() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try StorageSettingsService.saveFixedStorage(container.mainContext, directory)
        let settings = try container.mainContext.fetch(FetchDescriptor<StorageSettings>())
        let document = try makePDF()

        let first = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings,
            { _, _, _ in XCTFail("Fixed storage must not open a panel"); return nil }))
        let second = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent().resolvingSymlinksInPath().pathComponents, directory.resolvingSymlinksInPath().pathComponents)
        XCTAssertEqual(try Data(contentsOf: first), document.data)
        XCTAssertEqual(try Data(contentsOf: second), document.data)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).count, 2)
    }

    func testFlexibilityUsesSelectedDestinationAndRegistersIt() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Chosen name.pdf")
        let document = try makePDF()
        var panelWasOpened = false
        let result = try WebCaptureService.save(document, "Article", nil,
            container.mainContext, []) { title, _, data in
                panelWasOpened = true
                XCTAssertEqual(title, "Article")
                try XCTUnwrap(data).data.write(to: destination)
                return destination
            }
        XCTAssertTrue(panelWasOpened)
        XCTAssertEqual(result, destination)
        XCTAssertEqual(try Data(contentsOf: destination), document.data)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).first?.url, destination)
    }

    func testFixedStorageRecreatesMissingFolderAndRegistersPDF() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try StorageSettingsService.saveFixedStorage(container.mainContext, storage)
        let settings = try container.mainContext.fetch(FetchDescriptor<StorageSettings>())
        try FileManager.default.removeItem(at: storage)
        let document = try makePDF()

        let destination = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings,
            { _, _, _ in XCTFail("Fixed storage must not open a panel"); return nil }))

        XCTAssertEqual(destination.deletingLastPathComponent().resolvingSymlinksInPath(), storage.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: destination), document.data)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).first?.url, destination)
    }

    func testFixedStorageRecreatesMissingParentFoldersAndRegistersPDF() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("Parent", isDirectory: true)
        let storage = parent.appendingPathComponent("Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try StorageSettingsService.saveFixedStorage(container.mainContext, storage)
        let settings = try container.mainContext.fetch(FetchDescriptor<StorageSettings>())
        try FileManager.default.removeItem(at: parent)
        let document = try makePDF()

        let destination = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings))

        XCTAssertEqual(destination.deletingLastPathComponent().resolvingSymlinksInPath(), storage.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: destination), document.data)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).first?.url, destination)
    }

    func testFixedStorageDoesNotOverwriteFileBlockingMissingFolder() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let parent = directory.appendingPathComponent("Parent", isDirectory: true)
        let storage = parent.appendingPathComponent("Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try StorageSettingsService.saveFixedStorage(container.mainContext, storage)
        let settings = try container.mainContext.fetch(FetchDescriptor<StorageSettings>())
        try FileManager.default.removeItem(at: parent)
        let data = Data("Existing file".utf8)
        try data.write(to: parent)

        XCTAssertThrowsError(try WebCaptureService.save(makePDF(), "Article", nil,
            container.mainContext, settings))

        XCTAssertEqual(try Data(contentsOf: parent), data)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).isEmpty)
    }

    func testFixedStorageRecreatesFolderAfterMovingToICloudTrash() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let mobileDocuments = directory.appendingPathComponent("Library/Mobile Documents", isDirectory: true)
        let storage = mobileDocuments.appendingPathComponent("com~apple~CloudDocs/Storage", isDirectory: true)
        let trash = mobileDocuments.appendingPathComponent(".Trash/Storage", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: trash.deletingLastPathComponent(), withIntermediateDirectories: true)
        let existing = Data("Existing PDF".utf8)
        try existing.write(to: storage.appendingPathComponent("Article.pdf"))
        try StorageSettingsService.saveFixedStorage(container.mainContext, storage)
        let settings = try container.mainContext.fetch(FetchDescriptor<StorageSettings>())
        try FileManager.default.moveItem(at: storage, to: trash)
        let document = try makePDF()

        let first = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings))
        let second = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings))

        XCTAssertEqual(first.deletingLastPathComponent().resolvingSymlinksInPath(), storage.resolvingSymlinksInPath())
        XCTAssertEqual(second.deletingLastPathComponent().resolvingSymlinksInPath(), storage.resolvingSymlinksInPath())
        XCTAssertNotEqual(first, second)
        XCTAssertEqual(try Data(contentsOf: first), document.data)
        XCTAssertEqual(try Data(contentsOf: second), document.data)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 2)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: trash.path), ["Article.pdf"])
        XCTAssertEqual(try Data(contentsOf: trash.appendingPathComponent("Article.pdf")), existing)
    }

    func testFixedStorageFollowsRenamedFolderOutsideTrash() throws {
        let container = try makeContainer()
        let directory = try makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = directory.appendingPathComponent("Storage", isDirectory: true)
        let renamed = directory.appendingPathComponent("Renamed", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        try StorageSettingsService.saveFixedStorage(container.mainContext, storage)
        let settings = try container.mainContext.fetch(FetchDescriptor<StorageSettings>())
        try FileManager.default.moveItem(at: storage, to: renamed)
        let document = try makePDF()

        let destination = try XCTUnwrap(WebCaptureService.save(document, "Article", nil,
            container.mainContext, settings))

        XCTAssertEqual(destination.deletingLastPathComponent().resolvingSymlinksInPath(), renamed.resolvingSymlinksInPath())
        XCTAssertEqual(try Data(contentsOf: destination), document.data)
        XCTAssertFalse(FileManager.default.fileExists(atPath: storage.path))
    }

    func testCancelledPanelDoesNotRegisterPDF() throws {
        let container = try makeContainer()
        let result = try WebCaptureService.save(makePDF(), "Article", nil,
            container.mainContext, [],
            { _, _, _ in nil })
        XCTAssertNil(result)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).isEmpty)
    }

    func testMissingFixedFolderDoesNotFallBackToManualSave() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(try WebCaptureService.save(makePDF(), "Article", nil,
            container.mainContext, [StorageSettings(.fixed)],
            { _, _, _ in XCTFail("Must report the missing folder"); return nil }))
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).isEmpty)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: StorageSettings.self, PDFFile.self, PDFTag.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func makeDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func makePDF() throws -> PDFFileDocument {
        let data = NSMutableData()
        var box = CGRect(x: 0, y: 0, width: 100, height: 100)
        let consumer = try XCTUnwrap(CGDataConsumer(data: data))
        let context = try XCTUnwrap(CGContext(consumer: consumer, mediaBox: &box, nil))
        context.beginPDFPage(nil)
        context.endPDFPage()
        context.closePDF()
        return PDFFileDocument(data as Data)
    }
}
