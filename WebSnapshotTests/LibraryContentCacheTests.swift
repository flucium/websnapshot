import Foundation
import Combine
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class LibraryContentCacheTests: XCTestCase {
    @MainActor private lazy var sync = LibrarySyncService()

    func testRefreshRemovesDeletedPDFsAndPreservesExistingAndUnavailableEntries() async throws {
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
        try PDFTagService.replaceTags(["Keep", "Shared"], existing, context, sync: sync)
        try PDFTagService.replaceTags(["Remove", "Shared"], deleted, context, sync: sync)
        try PDFTagService.replaceTags(["Offline"], unavailable, context, sync: sync)
        XCTAssertEqual(unavailable.availability, .unavailable)

        let service = LibraryContentService(sync: sync, { _ in throw AppError.error("Extraction unavailable") })
        let task = try XCTUnwrap(service.refreshContentCache(context))
        try await task.value

        XCTAssertEqual(service.state.cacheRefreshResult?.removedCount, 1)
        let savedContext = ModelContext(container)
        let remaining = try savedContext.fetch(FetchDescriptor<PDFFile>())
        XCTAssertEqual(Set(remaining.map(\.url)), [existing.url, unavailable.url])
        XCTAssertTrue(remaining.allSatisfy { $0.searchableText == nil && $0.contentFingerprint == nil })
        XCTAssertEqual(remaining.first { $0.url == existing.url }?.addedAt, addedAt)
        XCTAssertEqual(Set(try savedContext.fetch(FetchDescriptor<PDFTag>()).map(\.name)), ["Keep", "Shared", "Offline"])
        XCTAssertEqual(try Data(contentsOf: fixture.url), originalData)
    }

    func testRefreshRebuildsTextAndReportsRemovedPDFs() async throws {
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

        let service = LibraryContentService(sync: sync)
        let task = try XCTUnwrap(service.refreshContentCache(container.mainContext))
        XCTAssertTrue(service.state.isRefreshingCache)
        try await task.value

        let result = try XCTUnwrap(service.state.cacheRefreshResult)
        XCTAssertEqual(result.refreshedCount, 1)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.unavailableCount, 0)
        XCTAssertTrue(LibraryService.matches(existing, "Fresh searchable content", .all))
        XCTAssertFalse(LibraryService.matches(existing, "Stale text", .all))
        XCTAssertEqual(try Data(contentsOf: fixture.url), originalData)
        XCTAssertFalse(service.state.isRefreshingCache)
        XCTAssertNil(service.cacheRefreshTask)
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
        let probe = CacheRefreshProbe()
        let service = LibraryContentService(sync: sync, { try await probe.read($0) })

        for _ in 0..<2 {
            let task = try XCTUnwrap(service.refreshContentCache(container.mainContext))
            try await task.value
            let result = try XCTUnwrap(service.state.cacheRefreshResult)
            XCTAssertEqual(result.refreshedCount, 1)
            XCTAssertEqual(result.removedCount, 0)
            XCTAssertEqual(result.unavailableCount, 1)
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

        let service = LibraryContentService(sync: sync)
        let task = try XCTUnwrap(service.refreshContentCache(container.mainContext))
        task.cancel()
        do {
            try await task.value
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        }

        XCTAssertEqual(entry.searchableText, "Existing cache")
        XCTAssertEqual(entry.contentFingerprint, "Existing fingerprint")
        XCTAssertFalse(service.state.isRefreshingCache)
        XCTAssertNil(service.cacheRefreshTask)
        XCTAssertNil(service.state.cacheRefreshResult)
    }

    func testRefreshRemovesPDFDeletedDuringExtractionAndIgnoresDuplicateStarts() async throws {
        let fixture = try ContentSearchFixture(["Existing content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try PDFTagService.replaceTags(["Temporary"], entry, container.mainContext, sync: sync)
        let started = expectation(description: "Refresh extraction started")
        let gate = CacheRefreshGate(started)
        let service = LibraryContentService(sync: sync, { _ in await gate.read() })

        let task = try XCTUnwrap(service.refreshContentCache(container.mainContext))
        await fulfillment(of: [started], timeout: 3)
        XCTAssertNil(service.refreshContentCache(container.mainContext))
        try FileManager.default.removeItem(at: fixture.url)
        await gate.finish()
        try await task.value

        let result = try XCTUnwrap(service.state.cacheRefreshResult)
        XCTAssertEqual(result.removedCount, 1)
        XCTAssertEqual(result.refreshedCount, 0)
        XCTAssertEqual(result.unavailableCount, 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFFile>()), 0)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<PDFTag>()), 0)
        let reads = await gate.reads
        XCTAssertEqual(reads, 1)
    }

    func testConcurrentIndexRequestsShareOneExtraction() async throws {
        let fixture = try ContentSearchFixture(["Existing content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let started = expectation(description: "Extraction started")
        let joined = expectation(description: "Second request started")
        let gate = CacheRefreshGate(started)
        let service = LibraryContentService(sync: sync, { _ in await gate.read() })

        var published: [LibraryContentState] = []
        let observation = service.$state.sink { published.append($0) }
        defer { observation.cancel() }
        let initialState = service.state

        let first = Task { await service.index([entry], container.mainContext) }
        await fulfillment(of: [started], timeout: 3)
        let second = Task {
            joined.fulfill()
            await service.index([entry], container.mainContext)
        }
        await fulfillment(of: [joined], timeout: 3)
        XCTAssertTrue(service.state.isIndexing)
        XCTAssertEqual(service.state.pendingCount, 1)
        let runningState = service.state
        await gate.finish()
        await first.value
        await second.value

        let reads = await gate.reads
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(entry.searchableText, "Extracted text")
        XCTAssertFalse(service.state.isIndexing)
        XCTAssertEqual(service.state.pendingCount, 0)
        XCTAssertFalse(initialState.isIndexing)
        XCTAssertEqual(initialState.pendingCount, 0)
        XCTAssertTrue(runningState.isIndexing)
        XCTAssertEqual(runningState.pendingCount, 1)
        XCTAssertTrue(published.contains { $0.isIndexing && $0.pendingCount == 1 })
        XCTAssertEqual(published.last?.isIndexing, false)
        XCTAssertEqual(published.last?.pendingCount, 0)
    }

    func testRefreshWaitsForIndexingAndPreventsOverlappingRequests() async throws {
        let fixture = try ContentSearchFixture(["Existing content"])
        defer { fixture.remove() }
        let container = try makeContainer()
        let entry = PDFFile(fixture.url)
        container.mainContext.insert(entry)
        try container.mainContext.save()
        let started = expectation(description: "Extraction started")
        let gate = CacheRefreshGate(started)
        let service = LibraryContentService(sync: sync, { _ in await gate.read() })

        let indexing = Task { await service.index([entry], container.mainContext) }
        await fulfillment(of: [started], timeout: 3)
        let refreshing = try XCTUnwrap(service.refreshContentCache(container.mainContext))
        XCTAssertNil(service.refreshContentCache(container.mainContext))
        await service.index([entry], container.mainContext)
        XCTAssertTrue(service.state.isRefreshingCache)
        let pendingReads = await gate.reads
        XCTAssertEqual(pendingReads, 1)
        await gate.finish()
        await indexing.value
        try await refreshing.value

        let reads = await gate.reads
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(entry.searchableText, "Extracted text")
        XCTAssertEqual(service.state.cacheRefreshResult?.refreshedCount, 1)
        XCTAssertEqual(service.state.failedCount, 0)
        XCTAssertEqual(service.state.pendingCount, 0)
        XCTAssertFalse(service.state.isIndexing)
        XCTAssertFalse(service.state.isRefreshingCache)
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
