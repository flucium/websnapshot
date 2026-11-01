import Foundation
import WebKit
import XCTest
@testable import WebSnapshot

@MainActor
final class WebNavigationTests: XCTestCase {
    func testProvisionalNetworkFailureIsPresentedAsRetryableNetworkError() async {
        let events = AsyncThrowingStream<WebPage.NavigationEvent, Error> { continuation in
            continuation.yield(.startedProvisionalNavigation)
            continuation.finish(throwing: WebPage.NavigationError.failedProvisionalNavigation(
                URLError(.notConnectedToInternet)
            ))
        }
        do {
            try await WebService.waitForNavigation(events)
            XCTFail("A failed load must not be returned as a success")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .network)
            XCTAssertEqual((error as? AppError)?.isRetryable, true)
        }
    }

    func testFinishedNavigationSucceeds() async throws {
        let events = AsyncThrowingStream<WebPage.NavigationEvent, Error> { continuation in
            continuation.yield(.startedProvisionalNavigation)
            continuation.yield(.committed)
            continuation.yield(.finished)
            continuation.finish()
        }
        try await WebService.waitForNavigation(events)
    }

    func testCancelledNavigationDoesNotProduceAnAlert() async {
        let events = AsyncThrowingStream<WebPage.NavigationEvent, Error> { continuation in
            continuation.finish(throwing: WebPage.NavigationError.failedProvisionalNavigation(
                URLError(.cancelled)
            ))
        }
        do {
            try await WebService.waitForNavigation(events)
            XCTFail("Cancellation must propagate")
        } catch {
            XCTAssertNil(AppError.presentable(error))
        }
    }

    func testUnfinishedNavigationTimesOutAndCancelsItsReader() async {
        let cancelled = expectation(description: "The navigation reader is cancelled")
        let events = AsyncThrowingStream<WebPage.NavigationEvent, Error> { continuation in
            continuation.yield(.startedProvisionalNavigation)
            continuation.onTermination = { _ in
                cancelled.fulfill()
            }
        }

        do {
            try await WebService.waitForNavigation(events, timeout: .milliseconds(20))
            XCTFail("A navigation that never finishes must time out")
        } catch {
            XCTAssertEqual((error as? AppError)?.kind, .timeout)
        }

        await fulfillment(of: [cancelled], timeout: 1)
    }

    func testCancellingAnUnfinishedNavigationDoesNotWaitForItsDeadline() async {
        let events = AsyncThrowingStream<WebPage.NavigationEvent, Error> { _ in }
        let task = Task {
            try await WebService.waitForNavigation(events)
        }

        await Task.yield()
        task.cancel()

        do {
            try await task.value
            XCTFail("Cancellation must stop waiting for navigation")
        } catch {
            XCTAssertNil(AppError.presentable(error))
        }
    }

    func testClearAndNewLoadsInvalidatePreviousRequests() {
        let state = FetchViewState()
        let first = state.beginLoad()
        let second = state.beginLoad()
        XCTAssertFalse(state.isCurrentLoad(first))
        state.finishLoad(first)
        XCTAssertTrue(state.isCurrentLoad(second))
        state.clear()
        XCTAssertFalse(state.isCurrentLoad(second))
    }

    func testNewLoadAndClearCancelPendingSavesWithoutAffectingLaterSaves() throws {
        let state = FetchViewState()
        let first = try XCTUnwrap(state.beginSave())
        XCTAssertNil(state.beginSave(), "Repeated Save clicks must not start concurrent exports")
        _ = state.beginLoad()
        XCTAssertFalse(state.isCurrentSave(first))
        XCTAssertFalse(state.isSaving)

        let second = try XCTUnwrap(state.beginSave())
        state.finishSave(first)
        XCTAssertTrue(state.isCurrentSave(second))
        XCTAssertTrue(state.isSaving)
        state.clear()
        XCTAssertFalse(state.isCurrentSave(second))
        XCTAssertFalse(state.isSaving)
    }
}
