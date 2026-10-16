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
    func testBatchImportCopiesAllPDFsWithUniqueNamesAndSelectsLastImport() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let importDirectory = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfData = try makePDFData()
        let existingURL = importDirectory.appendingPathComponent("Report.pdf")
        try pdfData.write(to: existingURL)
        let sources = try ["First", "Second"].map { name in
            let sourceDirectory = directory.appendingPathComponent(name)
            try FileManager.default.createDirectory(at: sourceDirectory, withIntermediateDirectories: true)
            let source = sourceDirectory.appendingPathComponent("Report.pdf")
            try pdfData.write(to: source)
            return source
        }
        let container = try ModelContainer(
            for: PDFFile.self, PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let state = LibraryViewState()
        state.searchText = "Hidden"
        state.selectedTag = .untagged
        state.appError = .error("Previous error")

        LibraryViewService.importPDFs(state, context, sources, importDirectory)

        let importedPDFs = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(Set(importedPDFs.map { $0.url.lastPathComponent }), ["Report 2.pdf", "Report 3.pdf"])
        XCTAssertEqual(importedPDFs.count, 2)
        for url in sources + importedPDFs.map(\.url) + [existingURL] {
            XCTAssertEqual(try Data(contentsOf: url), pdfData)
        }
        let selectedPDF = try XCTUnwrap(importedPDFs.first { $0.persistentModelID == state.selectedPDFRowID })
        XCTAssertEqual(selectedPDF.url.lastPathComponent, "Report 3.pdf")
        XCTAssertEqual(state.searchText, "")
        XCTAssertEqual(state.selectedTag, .all)
        XCTAssertNil(state.appError)
    }

    @MainActor
    func testBatchImportContinuesAfterFailuresAndReportsFailedFileNames() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let importDirectory = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let pdfData = try makePDFData()
        let sources = try ["First.pdf", "Invalid.pdf", "Second.pdf", "AlsoInvalid.pdf"].map { name in
            let source = directory.appendingPathComponent(name)
            try (name.contains("Invalid") ? Data("not a PDF".utf8) : pdfData).write(to: source)
            return source
        }
        let container = try ModelContainer(
            for: PDFFile.self, PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let state = LibraryViewState()

        LibraryViewService.importPDFs(state, context, sources, importDirectory)

        let importedPDFs = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(Set(importedPDFs.map { $0.url.lastPathComponent }), ["First.pdf", "Second.pdf"])
        XCTAssertEqual(importedPDFs.count, 2)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: importDirectory.path)), ["First.pdf", "Second.pdf"])
        let selectedPDF = try XCTUnwrap(importedPDFs.first { $0.persistentModelID == state.selectedPDFRowID })
        XCTAssertEqual(selectedPDF.url.lastPathComponent, "Second.pdf")
        let error = try XCTUnwrap(state.appError)
        XCTAssertTrue(error.userMessage.contains("2 of 4 PDFs were imported."))
        XCTAssertTrue(error.userMessage.contains("Invalid.pdf:"))
        XCTAssertTrue(error.userMessage.contains("AlsoInvalid.pdf:"))
    }

    @MainActor
    func testBatchImportFailurePreservesSelectionAndFilters() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let importDirectory = directory.appendingPathComponent("Library")
        try FileManager.default.createDirectory(at: importDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let sources = try ["Invalid.pdf", "AlsoInvalid.pdf"].map { name in
            let source = directory.appendingPathComponent(name)
            try Data("not a PDF".utf8).write(to: source)
            return source
        }
        let container = try ModelContainer(
            for: PDFFile.self, PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        let existingPDF = PDFFile(directory.appendingPathComponent("Existing.pdf"))
        context.insert(existingPDF)
        try context.save()
        let state = LibraryViewState()
        state.selectedPDFRowID = existingPDF.persistentModelID
        state.searchText = "Existing"
        state.selectedTag = .untagged

        LibraryViewService.importPDFs(state, context, sources, importDirectory)

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: importDirectory.path).isEmpty)
        XCTAssertEqual(state.selectedPDFRowID, existingPDF.persistentModelID)
        XCTAssertEqual(state.searchText, "Existing")
        XCTAssertEqual(state.selectedTag, .untagged)
        XCTAssertTrue(try XCTUnwrap(state.appError).userMessage.contains("0 of 2 PDFs were imported."))
    }

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
    func testImportRegistersPDFAlreadyInFixedStorageWithoutCopying() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = directory.appendingPathComponent("Report.pdf")
        let pdfData = try makePDFData()
        try pdfData.write(to: source)
        let container = try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            StorageSettings.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        try StorageSettingsService.saveFixedStorage(context, directory)
        let settings = try context.fetch(FetchDescriptor<StorageSettings>())
        let importDirectory = try XCTUnwrap(StorageSettingsService.fixedStorageURL(settings))

        let first = try LibraryViewService.importPDF(source, importDirectory, context)
        let pdfFile = try XCTUnwrap(context.fetch(FetchDescriptor<PDFFile>()).first)
        let entryID = pdfFile.persistentModelID
        let addedAt = try XCTUnwrap(pdfFile.addedAt)
        try PDFTagService.replaceTags(["Keep"], pdfFile, context)
        let second = try LibraryViewService.importPDF(source, importDirectory, context)

        XCTAssertEqual(first, source)
        XCTAssertEqual(second, source)
        XCTAssertEqual(try Data(contentsOf: source), pdfData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Report.pdf"])
        let importedPDFs = try context.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(importedPDFs.count, 1)
        XCTAssertEqual(importedPDFs.first?.persistentModelID, entryID)
        XCTAssertEqual(importedPDFs.first?.addedAt, addedAt)
        XCTAssertEqual(importedPDFs.first?.tags.map(\.name), ["Keep"])
    }

    @MainActor
    func testImportThroughDirectorySymlinkReusesPDFWithoutCopying() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let storage = directory.appendingPathComponent("Storage", isDirectory: true)
        let alias = directory.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: storage)

        let source = storage.appendingPathComponent("Report.pdf")
        let aliasedSource = alias.appendingPathComponent("Report.pdf")
        let pdfData = try makePDFData()
        try pdfData.write(to: source)
        let container = try ModelContainer(
            for: PDFFile.self,
            PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext

        let first = try LibraryViewService.importPDF(source, alias, context)
        let second = try LibraryViewService.importPDF(aliasedSource, storage, context)

        XCTAssertEqual(first, source)
        XCTAssertEqual(second, aliasedSource)
        XCTAssertEqual(try Data(contentsOf: source), pdfData)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: storage.path), ["Report.pdf"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 1)
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
        try PDFTagService.replaceTags(["Missing"], pdfFile, context)

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
