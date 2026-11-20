import Foundation
import AppKit
import Combine
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class SafariRequestServiceTests: XCTestCase {
    func testQueueChangesPublishWithoutChangingSnapshotsOrAnotherService() throws {
        let service = SafariRequestService { _, _, _ in nil }
        let other = SafariRequestService { _, _, _ in nil }
        let initialState = service.safariRequestState
        var publishedCounts: [Int] = []
        let observation = service.$safariRequestState.sink { publishedCounts.append($0.pending.count) }
        defer { observation.cancel() }

        service.receive(try makeRequest().openURL)
        var snapshot = service.safariRequestState
        snapshot.pending.removeAll()

        XCTAssertEqual(service.safariRequestState.pending.count, 1)
        XCTAssertTrue(snapshot.pending.isEmpty)
        XCTAssertTrue(initialState.pending.isEmpty)
        XCTAssertTrue(other.safariRequestState.pending.isEmpty)
        XCTAssertEqual(publishedCounts, [0, 1])
    }

    func testDeliveryIsDeduplicatedButSeparateClicksOnSameURLAreQueued() throws {
        let service = SafariRequestService { _, _, _ in nil }
        let request = try makeRequest()
        service.receive(request.openURL)
        service.receive(request.openURL)
        service.receive(try makeRequest().openURL)
        XCTAssertEqual(service.safariRequestState.pending.count, 2)
        XCTAssertNil(service.safariRequestState.appError)
    }

    func testRequestsRunSeriallyAndFailurePausesQueueUntilRetry() async throws {
        let container = try makeContainer()
        var attempts: [URL] = []
        let service = SafariRequestService { url, _, _ in
            attempts.append(url)
            if attempts.count == 1 { throw AppError.invalidNetwork("Offline") }
            return URL(fileURLWithPath: "/tmp/result.pdf")
        }
        let first = try makeRequest("https://example.com/first")
        let second = try makeRequest("https://example.com/second")
        service.receive(first.openURL)
        service.receive(second.openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { service.safariRequestState.appError != nil }
        XCTAssertEqual(attempts, [first.url])
        XCTAssertEqual(service.safariRequestState.pending, [second])
        XCTAssertTrue(service.canRetry)

        service.retry(container.mainContext)
        try await waitUntil { service.safariRequestState.pending.isEmpty && service.safariRequestState.current == nil }
        XCTAssertEqual(attempts, [first.url, first.url, second.url])
        XCTAssertNil(service.safariRequestState.appError)
        XCTAssertNotNil(service.safariRequestState.savedURL)
    }

    func testClosingCaptureCancelsActiveWorkAndClearsQueue() async throws {
        let container = try makeContainer()
        var started = false
        let service = SafariRequestService { _, _, _ in
            started = true
            try await Task.sleep(for: .seconds(30))
            XCTFail("Cancelled capture must not finish saving")
            return nil
        }
        service.receive(try makeRequest().openURL)
        service.receive(try makeRequest().openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { started }
        service.cancel()
        try await waitUntil { service.safariRequestState.current == nil }
        XCTAssertTrue(service.safariRequestState.pending.isEmpty)
        XCTAssertNil(service.safariRequestState.appError)
        XCTAssertNil(service.safariRequestState.savedURL)
    }

    func testWindowlessFailureCanRetryAndFinishQueuedRequests() async throws {
        let container = try makeContainer()
        var attempts: [URL] = []
        var failureCount = 0
        let service = SafariRequestService { url, _, _ in
            attempts.append(url)
            if failureCount == 0 {
                failureCount += 1
                throw AppError.invalidNetwork("Offline")
            }
            return URL(fileURLWithPath: "/tmp/result.pdf")
        }
        var reportedErrors: [String] = []
        service.handleFailure = { error in
            reportedErrors.append(error.userMessage)
            return .retry
        }

        let first = try makeRequest("https://example.com/first")
        let second = try makeRequest("https://example.com/second")
        service.receive(first.openURL)
        service.receive(second.openURL)
        service.startProcessing(container.mainContext)

        try await waitUntil { attempts.count == 3 && service.safariRequestState.current == nil }
        XCTAssertEqual(attempts, [first.url, first.url, second.url])
        XCTAssertEqual(reportedErrors, ["Offline"])
        XCTAssertNil(service.safariRequestState.appError)
        XCTAssertTrue(service.safariRequestState.pending.isEmpty)
    }

    func testWindowlessFailureCanSkipAndContinueQueue() async throws {
        let container = try makeContainer()
        var attempts: [URL] = []
        let service = SafariRequestService { url, _, _ in
            attempts.append(url)
            if url.path == "/first" {
                throw AppError.invalidNetwork("Offline")
            }
            return URL(fileURLWithPath: "/tmp/result.pdf")
        }
        service.handleFailure = { _ in .skip }

        let first = try makeRequest("https://example.com/first")
        let second = try makeRequest("https://example.com/second")
        service.receive(first.openURL)
        service.receive(second.openURL)
        service.startProcessing(container.mainContext)

        try await waitUntil { attempts.count == 2 && service.safariRequestState.current == nil }
        XCTAssertEqual(attempts, [first.url, second.url])
        XCTAssertNil(service.safariRequestState.appError)
        XCTAssertTrue(service.safariRequestState.pending.isEmpty)
    }

    func testProgressIsPublishedAndClearedAfterCapture() async throws {
        let container = try makeContainer()
        let service = SafariRequestService { _, _, _, onProgress in
            onProgress(WebPDFExportState(phase: .resources, height: 2000, pendingImages: 2))
            try await Task.sleep(for: .milliseconds(30))
            return nil
        }

        service.receive(try makeRequest().openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { service.safariRequestState.exportState?.phase == .resources }

        XCTAssertEqual(service.safariRequestState.exportState?.pendingImages, 2)
        XCTAssertEqual(service.safariRequestState.status, "Waiting for Images and Fonts")

        try await waitUntil { service.safariRequestState.current == nil }
        XCTAssertNil(service.safariRequestState.exportState)
        XCTAssertNil(service.safariRequestState.webPage)
        XCTAssertFalse(service.safariRequestState.isCancelling)
    }

    func testCancellationDiscardsLateProgressAndResultsBeforeTheNextRequest() async throws {
        let container = try makeContainer()
        var finishFirst: CheckedContinuation<Void, Never>?
        var attempts: [URL] = []
        let first = try makeRequest("https://example.com/first")
        let skipped = try makeRequest("https://example.com/skipped")
        let next = try makeRequest("https://example.com/next")
        let service = SafariRequestService { url, _, _, onProgress in
            attempts.append(url)
            if url == first.url {
                onProgress(WebPDFExportState(height: 1000))
                await withCheckedContinuation { finishFirst = $0 }
                onProgress(WebPDFExportState(height: 9000))
                return URL(fileURLWithPath: "/tmp/cancelled-result.pdf")
            }

            onProgress(WebPDFExportState(height: 2000))
            return nil
        }
        var reportedHeights: [Double] = []
        let observation = service.$safariRequestState.sink {
            if let progress = $0.exportState {
                reportedHeights.append(progress.height)
            }
        }
        defer { observation.cancel() }

        service.receive(first.openURL)
        service.receive(skipped.openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { finishFirst != nil }
        service.cancel()
        XCTAssertTrue(service.safariRequestState.isCancelling)

        service.receive(next.openURL)
        service.startProcessing(container.mainContext)
        finishFirst?.resume()
        try await waitUntil { service.safariRequestState.pending.isEmpty && service.safariRequestState.current == nil }

        XCTAssertEqual(attempts, [first.url, next.url])
        XCTAssertFalse(reportedHeights.contains(9000))
        XCTAssertNil(service.safariRequestState.savedURL)
        XCTAssertNil(service.safariRequestState.appError)
        XCTAssertNil(service.safariRequestState.exportState)
        XCTAssertFalse(service.safariRequestState.isCancelling)
    }

    func testCancellationDuringFailureHandlingDoesNotRequeueTheRequest() async throws {
        let container = try makeContainer()
        var attempts = 0
        let service = SafariRequestService { _, _, _ in
            attempts += 1
            throw AppError.timeout("The page kept growing")
        }
        service.handleFailure = { _ in
            service.cancel()
            return .retry
        }
        defer { service.handleFailure = nil }

        service.receive(try makeRequest().openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { service.safariRequestState.pending.isEmpty && service.safariRequestState.current == nil }

        XCTAssertEqual(attempts, 1)
        XCTAssertNil(service.safariRequestState.appError)
        XCTAssertEqual(service.safariRequestState.status, "Save cancelled.")
    }

    func testClosingProgressWindowCancelsCaptureAndQueuedRequests() async throws {
        let container = try makeContainer()
        let service = SafariRequestService { _, _, _, onProgress in
            onProgress(WebPDFExportState(height: 12_000))
            try await Task.sleep(for: .seconds(30))
            XCTFail("Closing the progress window must cancel capture")
            return nil
        }
        service.receive(try makeRequest().openURL)
        service.receive(try makeRequest("https://example.com/next").openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { service.safariRequestState.exportState != nil }

        let controller = SafariCaptureProgressWindow(service)
        controller.update()
        defer { controller.close() }

        let window = try XCTUnwrap(controller.window)
        XCTAssertTrue(window.isVisible)

        if let path = ProcessInfo.processInfo.environment["WEBSNAPSHOT_SAFARI_PROGRESS_PREVIEW_PATH"], let view = window.contentView {
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: path))
        }

        window.performClose(nil)
        controller.update()
        XCTAssertFalse(window.isVisible)
        try await waitUntil { service.safariRequestState.current == nil }
        XCTAssertTrue(service.safariRequestState.pending.isEmpty)
        XCTAssertNil(service.safariRequestState.appError)
    }

    private func makeRequest(_ address: String = "https://example.com") throws -> SafariCaptureRequest {
        try SafariCaptureRequest(id: UUID(), url: XCTUnwrap(URL(string: address)))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: StorageSettings.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out waiting for capture state")
    }
}
