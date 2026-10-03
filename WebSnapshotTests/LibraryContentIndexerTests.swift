import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryContentIndexerTests: XCTestCase {
    func testLegacyEntryBecomesSearchableAndDoesNotNeedReindexing() async throws {
        let fixture = try ContentSearchFixture(["Text found only inside the PDF"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(fixture.url)
        context.insert(entry)
        try context.save()
        XCTAssertNil(entry.searchableText)

        await LibraryContentIndexer().index([entry], context)
        XCTAssertTrue(LibraryViewService.matches(entry, "inside the PDF", .all))
        XCTAssertFalse(LibraryViewService.matches(entry, "inside the PDF", .title))
        XCTAssertFalse(LibraryViewService.matches(entry, "inside the PDF", .tag))

        let probe = ExtractionProbe()
        await LibraryContentIndexer(extract: { try await probe.read($0) }).index([entry], context)
        let reads = await probe.reads
        XCTAssertEqual(reads, 0)
    }

    func testAllSearchIncludesContentWhileTitleAndTagStayFocused() {
        let entry = PDFFile(URL(fileURLWithPath: "/tmp/Report.pdf"))
        entry.tags = [PDFTag("Research", normalizedName: "research")]
        entry.searchableText = "本文には日本語と Searchable Text が含まれます"

        XCTAssertTrue(LibraryViewService.matches(entry, "  searchable text  ", .all))
        XCTAssertTrue(LibraryViewService.matches(entry, "日本語", .all))
        XCTAssertTrue(LibraryViewService.matches(entry, "report", .all))
        XCTAssertTrue(LibraryViewService.matches(entry, "research", .all))
        XCTAssertTrue(LibraryViewService.matches(entry, "REPORT", .title))
        XCTAssertTrue(LibraryViewService.matches(entry, "RESEARCH", .tag))
        XCTAssertFalse(LibraryViewService.matches(entry, "日本語", .title))
        XCTAssertFalse(LibraryViewService.matches(entry, "日本語", .tag))
        XCTAssertTrue(LibraryViewService.matches(entry, " \n ", .all))
        entry.searchableText = nil
        XCTAssertFalse(LibraryViewService.matches(entry, "日本語", .all))
    }

    func testCacheSurvivesReopeningTheStore() async throws {
        let fixture = try ContentSearchFixture(["Persisted content"])
        defer { fixture.remove() }
        let configuration = ModelConfiguration(url: fixture.directory.appendingPathComponent("Library.store"))
        try await populateStore(configuration, fixture.url)

        let reopened = try ModelContainer(for: PDFFile.self, PDFTag.self, configurations: configuration)
        let entry = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertTrue(entry.searchableText?.contains("Persisted content") ?? false)
        let probe = ExtractionProbe()
        await LibraryContentIndexer(extract: { try await probe.read($0) }).index([entry], reopened.mainContext)
        let reads = await probe.reads
        XCTAssertEqual(reads, 0)
    }

    func testStoreWithoutContentFieldsMigratesAndKeepsTags() async throws {
        let fixture = try ContentSearchFixture(["Existing PDF content"])
        defer { fixture.remove() }
        let configuration = ModelConfiguration(url: fixture.directory.appendingPathComponent("Legacy.store"))
        try populateLegacyStore(configuration, fixture.url)

        let container = try ModelContainer(for: PDFFile.self, PDFTag.self, configurations: configuration)
        let entry = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<PDFFile>()).first)
        XCTAssertEqual(entry.url, fixture.url)
        XCTAssertEqual(entry.tags.map(\.name), ["Keep"])
        XCTAssertNil(entry.searchableText)
        await LibraryContentIndexer().index([entry], container.mainContext)
        XCTAssertTrue(LibraryViewService.matches(entry, "Existing PDF content", .all))
    }

    func testUpdatedPDFReplacesOldContent() async throws {
        let fixture = try ContentSearchFixture(["Original content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let indexer = LibraryContentIndexer()
        await indexer.index([entry], container.mainContext)

        try ContentSearchFixture.data(["Replacement content"]).write(to: fixture.url, options: .atomic)
        await indexer.index([entry], container.mainContext)

        XCTAssertTrue(LibraryViewService.matches(entry, "Replacement", .all))
        XCTAssertFalse(LibraryViewService.matches(entry, "Original", .all))
    }

    func testChangedPDFDoesNotReceiveAStaleExtraction() async throws {
        let fixture = try ContentSearchFixture(["Original content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let replacement = try ContentSearchFixture.data(["Replacement content"])
        let indexer = LibraryContentIndexer(extract: { url in
            try replacement.write(to: url, options: .atomic)
            return "Original content"
        })

        await indexer.index([entry], container.mainContext)

        XCTAssertNil(entry.searchableText)
        XCTAssertNil(entry.contentFingerprint)
        XCTAssertEqual(indexer.pendingCount, 0)
        await LibraryContentIndexer().index([entry], container.mainContext)
        XCTAssertTrue(LibraryViewService.matches(entry, "Replacement", .all))
    }

    func testDeletedEntryDoesNotGetRecreatedAfterExtraction() async throws {
        let fixture = try ContentSearchFixture(["Original content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let context = container.mainContext
        let entry = PDFFile(fixture.url)
        context.insert(entry)
        try context.save()
        let started = expectation(description: "Extraction started")
        let gate = ExtractionGate(started)
        let indexer = LibraryContentIndexer(extract: { _ in await gate.read() })
        let task = Task { await indexer.index([entry], context) }
        await fulfillment(of: [started], timeout: 3)
        context.delete(entry)
        try context.save()
        await gate.finish()
        await task.value

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PDFFile>()), 0)
    }

    func testFailureIsSkippedUntilRetryAndDoesNotBlockOtherPDFs() async throws {
        let fixture = try ContentSearchFixture(["Valid content"])
        defer { fixture.remove() }
        let invalidURL = fixture.directory.appendingPathComponent("Invalid.pdf")
        try Data("Not a PDF".utf8).write(to: invalidURL)
        let container = try makeContainer()
        let invalid = PDFFile(invalidURL)
        let valid = PDFFile(fixture.url)
        container.mainContext.insert(invalid)
        container.mainContext.insert(valid)
        try container.mainContext.save()
        let probe = ExtractionProbe()
        let indexer = LibraryContentIndexer(extract: { try await probe.read($0) })

        await indexer.index([invalid, valid], container.mainContext)
        await indexer.index([invalid, valid], container.mainContext)
        let reads = await probe.reads
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(indexer.failedCount, 1)
        XCTAssertNil(invalid.searchableText)
        XCTAssertTrue(valid.searchableText?.contains("Valid content") ?? false)

        indexer.retry()
        await indexer.index([invalid, valid], container.mainContext)
        let retriedReads = await probe.reads
        XCTAssertEqual(retriedReads, 3)
    }

    func testBlankTextIsCachedAndCancellationIsNotCachedAsFailure() async throws {
        let fixture = try ContentSearchFixture([""])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let cancelled = LibraryContentIndexer(extract: { _ in throw CancellationError() })
        await cancelled.index([entry], container.mainContext)
        XCTAssertNil(entry.searchableText)
        XCTAssertEqual(cancelled.failedCount, 0)

        let probe = ExtractionProbe()
        let indexer = LibraryContentIndexer(extract: { try await probe.read($0) })
        await indexer.index([entry], container.mainContext)
        await indexer.index([entry], container.mainContext)
        let reads = await probe.reads
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(entry.searchableText, "")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: PDFFile.self, PDFTag.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func populateStore(_ configuration: ModelConfiguration, _ url: URL) async throws {
        let container = try ModelContainer(for: PDFFile.self, PDFTag.self, configurations: configuration)
        let entry = PDFFile(url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        await LibraryContentIndexer().index([entry], container.mainContext)
    }

    private func populateLegacyStore(_ configuration: ModelConfiguration, _ url: URL) throws {
        let container = try ModelContainer(for: LegacyLibraryModels.PDFFile.self,
                                           LegacyLibraryModels.PDFTag.self, configurations: configuration)
        let entry = LegacyLibraryModels.PDFFile(url)
        entry.tags = [LegacyLibraryModels.PDFTag("Keep", normalizedName: "keep")]
        container.mainContext.insert(entry)
        try container.mainContext.save()
    }
}

private enum LegacyLibraryModels {
    @Model final class PDFFile {
        var url: URL
        var bookmarkData: Data?
        var addedAt: Date? = nil
        var tags: [PDFTag] = []

        init(_ url: URL) { self.url = url }
    }

    @Model final class PDFTag {
        @Attribute(.unique) var normalizedName: String
        @Relationship(inverse: \PDFFile.tags) var pdfFiles: [PDFFile] = []
        var name: String

        init(_ name: String, normalizedName: String) {
            self.name = name
            self.normalizedName = normalizedName
        }
    }
}

private actor ExtractionProbe {
    var reads = 0

    func read(_ url: URL) async throws -> String {
        reads += 1
        return try await PDFContentService().text(url)
    }
}

private actor ExtractionGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<String, Never>?
    private var finished = false

    init(_ started: XCTestExpectation) {
        self.started = started
    }

    func read() async -> String {
        if finished { return "Original content" }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func finish() {
        finished = true
        continuation?.resume(returning: "Original content")
        continuation = nil
    }
}
