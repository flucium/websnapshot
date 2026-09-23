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

        let first = try XCTUnwrap(WebCaptureService.save(document, title: "Article", url: nil,
            modelContext: container.mainContext, storageSettings: settings,
            chooseDestination: { _, _, _ in XCTFail("Fixed storage must not open a panel"); return nil }))
        let second = try XCTUnwrap(WebCaptureService.save(document, title: "Article", url: nil,
            modelContext: container.mainContext, storageSettings: settings))

        XCTAssertNotEqual(first, second)
        XCTAssertEqual(first.deletingLastPathComponent(), directory)
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
        let result = try WebCaptureService.save(document, title: "Article", url: nil,
            modelContext: container.mainContext, storageSettings: []) { title, _, data in
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

    func testCancelledPanelDoesNotRegisterPDF() throws {
        let container = try makeContainer()
        let result = try WebCaptureService.save(makePDF(), title: "Article", url: nil,
            modelContext: container.mainContext, storageSettings: [],
            chooseDestination: { _, _, _ in nil })
        XCTAssertNil(result)
        XCTAssertTrue(try container.mainContext.fetch(FetchDescriptor<PDFFile>()).isEmpty)
    }

    func testMissingFixedFolderDoesNotFallBackToManualSave() throws {
        let container = try makeContainer()
        XCTAssertThrowsError(try WebCaptureService.save(makePDF(), title: "Article", url: nil,
            modelContext: container.mainContext, storageSettings: [StorageSettings(.fixed)],
            chooseDestination: { _, _, _ in XCTFail("Must report the missing folder"); return nil }))
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
