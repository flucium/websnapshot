import Foundation
import SwiftData
import XCTest
@testable import WebSnapshot

@MainActor
final class SafariRequestServiceTests: XCTestCase {
    func testDeliveryIsDeduplicatedButSeparateClicksOnSameURLAreQueued() throws {
        let service = SafariRequestService { _, _, _ in nil }
        let request = try makeRequest()
        service.receive(request.openURL)
        service.receive(request.openURL)
        service.receive(try makeRequest().openURL)
        XCTAssertEqual(service.pending.count, 2)
        XCTAssertNil(service.appError)
    }

    func testRequestsRunSeriallyAndFailurePausesQueueUntilRetry() async throws {
        let container = try makeContainer()
        var attempts: [URL] = []
        var shouldFail = true
        let service = SafariRequestService { url, _, _ in
            attempts.append(url)
            if shouldFail { throw AppError.invalidNetwork("Offline") }
            return URL(fileURLWithPath: "/tmp/result.pdf")
        }
        let first = try makeRequest("https://example.com/first")
        let second = try makeRequest("https://example.com/second")
        service.receive(first.openURL)
        service.receive(second.openURL)
        service.startProcessing(container.mainContext)
        try await waitUntil { service.appError != nil }
        XCTAssertEqual(attempts, [first.url])
        XCTAssertEqual(service.pending, [second])
        XCTAssertTrue(service.canRetry)

        shouldFail = false
        service.retry(container.mainContext)
        try await waitUntil { service.pending.isEmpty && service.current == nil }
        XCTAssertEqual(attempts, [first.url, first.url, second.url])
        XCTAssertNil(service.appError)
        XCTAssertNotNil(service.savedURL)
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
        try await waitUntil { service.current == nil }
        XCTAssertTrue(service.pending.isEmpty)
        XCTAssertNil(service.appError)
        XCTAssertNil(service.savedURL)
    }

    private func makeRequest(_ address: String = "https://example.com") throws -> SafariCaptureRequest {
        try SafariCaptureRequest(id: UUID(), url: XCTUnwrap(URL(string: address)))
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: StorageSettings.self,
                           configurations: ModelConfiguration(isStoredInMemoryOnly: true))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }
        XCTAssertTrue(condition(), "Timed out waiting for capture state")
    }
}
