import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class SettingsContentCacheTests: XCTestCase {
    func testInvalidationRemovesDeletedPDFsAndPreservesExistingAndUnavailableEntries() throws {
        let fixture = try ContentSearchFixture(["Existing content"])
        defer { fixture.remove() }
        let originalData = try Data(contentsOf: fixture.url)
        let container = try makeContainer()
        let context = container.mainContext
        let addedAt = Date(timeIntervalSince1970: 12345)
        let existing = PDFFile(fixture.url, nil, addedAt)
        let deleted = PDFFile(fixture.directory.appendingPathComponent("Deleted.pdf"))
        let unavailable = PDFFile(fixture.directory.appendingPathComponent("Offline/Report.pdf"))
        for entry in [existing, deleted, unavailable] {
            entry.searchableText = "Old cached text"
            entry.contentFingerprint = "Old fingerprint"
            context.insert(entry)
        }
        try PDFTagService.replaceTags(["Keep", "Shared"], for: existing, in: context)
        try PDFTagService.replaceTags(["Remove", "Shared"], for: deleted, in: context)
        try PDFTagService.replaceTags(["Offline"], for: unavailable, in: context)
        XCTAssertEqual(unavailable.availability, .unavailable)

        let removedCount = try SettingsViewService.invalidateContentCache(context)

        XCTAssertEqual(removedCount, 1)
        let savedContext = ModelContext(container)
        let remaining = try savedContext.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(Set(remaining.map(\.url)), [existing.url, unavailable.url])
        XCTAssertTrue(remaining.allSatisfy { $0.searchableText == nil && $0.contentFingerprint == nil })
        XCTAssertEqual(remaining.first { $0.url == existing.url }?.addedAt, addedAt)
        XCTAssertEqual(Set(try savedContext.fetch(FetchDescriptor<PDFTag>()).map(\.name)), ["Keep", "Shared", "Offline"])
        XCTAssertEqual(try Data(contentsOf: fixture.url), originalData)
    }

    func testRefreshRebuildsTextInSettingsAndReportsRemovedPDFs() async throws {
        let fixture = try ContentSearchFixture(["Fresh searchable content"])
        defer { fixture.remove() }
        let originalData = try Data(contentsOf: fixture.url)
        let container = try makeContainer()
        let existing = PDFFile(fixture.url)
        existing.searchableText = "Stale text"
        existing.contentFingerprint = try PDFContentService.fingerprint(fixture.url)
        container.mainContext.insert(existing)
        container.mainContext.insert(PDFFile(fixture.directory.appendingPathComponent("Deleted.pdf")))
        try container.mainContext.save()
        let state = SettingsViewState()

        SettingsViewService.refreshContentCache(state, container.mainContext, LibraryContentIndexer())
        XCTAssertTrue(state.isRefreshingCache)
        let task = try XCTUnwrap(state.cacheRefreshTask)
        await task.value

        let result = try XCTUnwrap(state.cacheRefreshResult)
        XCTAssertEqual(result.refreshedCount, 1)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.unavailableCount, 0)
        XCTAssertTrue(LibraryViewService.matches(existing, "Fresh searchable content", .all))
        XCTAssertFalse(LibraryViewService.matches(existing, "Stale text", .all))
        XCTAssertEqual(try Data(contentsOf: fixture.url), originalData)
        XCTAssertFalse(state.isRefreshingCache)
        XCTAssertNil(state.cacheRefreshTask)
        XCTAssertNil(state.appError)
    }

    func testRefreshRetriesFailuresAndReportsPartialResults() async throws {
        let fixture = try ContentSearchFixture(["Valid content"])
        defer { fixture.remove() }
        let invalidURL = fixture.directory.appendingPathComponent("Invalid.pdf")
        try Data("Not a PDF".utf8).write(to: invalidURL)
        let container = try makeContainer()
        container.mainContext.insert(PDFFile(fixture.url))
        container.mainContext.insert(PDFFile(invalidURL))
        try container.mainContext.save()
        let state = SettingsViewState()
        let probe = CacheRefreshProbe()
        let indexer = LibraryContentIndexer(extract: { try await probe.read($0) })

        for _ in 0..<2 {
            SettingsViewService.refreshContentCache(state, container.mainContext, indexer)
            let task = try XCTUnwrap(state.cacheRefreshTask)
            await task.value
            let result = try XCTUnwrap(state.cacheRefreshResult)
            XCTAssertEqual(result.refreshedCount, 1)
            XCTAssertEqual(result.removedCount, 0)
            XCTAssertEqual(result.unavailableCount, 1)
            XCTAssertNil(state.appError)
        }
        let reads = await probe.reads
        XCTAssertEqual(reads, 4)
    }

    func testCancellationBeforeStartingPreservesCacheAndResetsBusyState() async throws {
        let fixture = try ContentSearchFixture(["Existing content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        entry.searchableText = "Existing cache"
        entry.contentFingerprint = "Existing fingerprint"
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let state = SettingsViewState()

        SettingsViewService.refreshContentCache(state, container.mainContext, LibraryContentIndexer())
        let task = try XCTUnwrap(state.cacheRefreshTask)
        task.cancel()
        await task.value

        XCTAssertEqual(entry.searchableText, "Existing cache")
        XCTAssertEqual(entry.contentFingerprint, "Existing fingerprint")
        XCTAssertFalse(state.isRefreshingCache)
        XCTAssertNil(state.cacheRefreshTask)
        XCTAssertNil(state.cacheRefreshResult)
        XCTAssertNil(state.appError)
    }

    func testRefreshRemovesPDFDeletedDuringExtractionAndIgnoresDuplicateStarts() async throws {
        let fixture = try ContentSearchFixture(["Existing content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try PDFTagService.replaceTags(["Temporary"], for: entry, in: container.mainContext)
        let started = expectation(description: "Refresh extraction started")
        let gate = CacheRefreshGate(started)
        let state = SettingsViewState()
        let indexer = LibraryContentIndexer(extract: { _ in await gate.read() })

        SettingsViewService.refreshContentCache(state, container.mainContext, indexer)
        let task = try XCTUnwrap(state.cacheRefreshTask)
        await fulfillment(of: [started], timeout: 3)
        SettingsViewService.refreshContentCache(state, container.mainContext, indexer)
        try FileManager.default.removeItem(at: fixture.url)
        await gate.finish()
        await task.value

        let result = try XCTUnwrap(state.cacheRefreshResult)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.refreshedCount, 0)
        XCTAssertEqual(result.unavailableCount, 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFTag>()), 0)
        let reads = await gate.reads
        XCTAssertEqual(reads, 1)
        XCTAssertNil(state.appError)
    }

    private func makeContainer() throws -> ModelContainer {
        let container = try ModelContainer(
            for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        container.mainContext.autosaveEnabled = false
        return container
    }
}

private actor CacheRefreshProbe {
    var reads = 0

    func read(_ url: URL) throws -> String {
        reads += 1
        if url.lastPathComponent == "Invalid.pdf" { throw AppError.invalidFileType("Invalid PDF") }
        return "Fresh searchable text"
    }
}

private actor CacheRefreshGate {
    let started: XCTestExpectation
    private var continuation: CheckedContinuation<String, Never>?
    private var finished = false
    var reads = 0

    init(_ started: XCTestExpectation) { self.started = started }

    func read() async -> String {
        reads += 1
        if finished { return "Extracted text" }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            started.fulfill()
        }
    }

    func finish() {
        finished = true
        continuation?.resume(returning: "Extracted text")
        continuation = nil
    }
}
