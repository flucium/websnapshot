import AppKit
import Foundation
import SwiftData
import SwiftUI
import XCTest

@testable import WebSnapshot

@MainActor
final class LibraryStartupServiceTests: XCTestCase {
    func testInitializationWaitsForAnExplicitOpen() {
        var attempts = 0
        let startup = LibraryStartupService {
            attempts += 1
            throw CocoaError(.fileReadNoPermission)
        }

        guard case .idle = startup.state else {
            return XCTFail("The library must wait for startup")
        }

        XCTAssertEqual(attempts, 0)
        XCTAssertNil(startup.modelContainer)
    }

    func testFailedOpenKeepsErrorDetailsAndCanFailAgain() async {
        var attempts = 0
        let startup = LibraryStartupService {
            attempts += 1
            throw CocoaError(attempts == 1 ? .fileReadNoPermission : .fileWriteOutOfSpace)
        }

        await startup.open()

        guard case .failed(let firstError) = startup.state else {
            return XCTFail("An unavailable library must show recovery")
        }

        XCTAssertNil(startup.modelContainer)
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(firstError.underlyingError?.domain, NSCocoaErrorDomain)
        XCTAssertEqual(firstError.underlyingError?.code, CocoaError.fileReadNoPermission.rawValue)
        XCTAssertTrue(firstError.diagnosticMessage.contains(NSCocoaErrorDomain))

        await startup.open()

        guard case .failed(let secondError) = startup.state else {
            return XCTFail("A failed retry must keep recovery available")
        }

        XCTAssertNil(startup.modelContainer)
        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(secondError.underlyingError?.code, CocoaError.fileWriteOutOfSpace.rawValue)
        XCTAssertNotEqual(firstError.id, secondError.id)
    }

    func testRetryReopensTheExistingStoreWithItsSettingsAndTags() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Library.store"), cloudKitDatabase: .none)

        try autoreleasepool {
            let container = try makeContainer(configuration)
            let context = container.mainContext
            let pdf = PDFFile(directory.appendingPathComponent("Article.pdf"))
            let tag = PDFTag("Saved Tag", normalizedName: "saved tag")
            context.insert(pdf)
            context.insert(tag)
            pdf.tags = [tag]
            context.insert(AppearanceSettings(.dark))
            context.insert(StorageSettings(.flexibility))
            try context.save()
        }

        var attempts = 0
        let startup = LibraryStartupService {
            attempts += 1
            if attempts == 1 {
                throw CocoaError(.fileReadNoPermission)
            }

            return try self.makeContainer(configuration)
        }

        await startup.open()
        XCTAssertNil(startup.modelContainer)

        await startup.open()

        let container = try XCTUnwrap(startup.modelContainer)
        let context = container.mainContext
        let pdfs = try context.fetch(FetchDescriptor<PDFFile>())
        let appearances = try context.fetch(FetchDescriptor<AppearanceSettings>())
        let settings = try context.fetch(FetchDescriptor<StorageSettings>())

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(pdfs.count, 1)
        XCTAssertEqual(pdfs.first?.url, directory.appendingPathComponent("Article.pdf"))
        XCTAssertEqual(pdfs.first?.tags.map(\.name), ["Saved Tag"])
        XCTAssertEqual(appearances.count, 1)
        XCTAssertEqual(appearances.first?.appearance, .dark)
        XCTAssertEqual(settings.count, 1)
        XCTAssertEqual(settings.first?.storage, .flexibility)
    }

    func testRecoveryViewRendersWithoutAModelContainerOrAutomaticRetry() async throws {
        let startup = LibraryStartupService {
            throw CocoaError(.fileReadNoPermission)
        }
        await startup.open()

        var retries = 0
        let hostingView = NSHostingView(rootView: DatabaseRecoveryView(startup: startup) {
            retries += 1
        })
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }

        for _ in 0..<10 {
            hostingView.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(20))
        }

        let bitmap = try XCTUnwrap(hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds))
        hostingView.cacheDisplay(in: hostingView.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        XCTAssertGreaterThan(bitmap.pixelsWide, 0)
        XCTAssertGreaterThan(bitmap.pixelsHigh, 0)
        XCTAssertFalse(data.isEmpty)

        if let path = ProcessInfo.processInfo.environment["WEBSNAPSHOT_RECOVERY_PREVIEW_PATH"] {
            try data.write(to: URL(fileURLWithPath: path))
        }

        XCTAssertEqual(retries, 0)
        XCTAssertNil(startup.modelContainer)
    }

    func testConcurrentRequestsAndRepeatedOpenKeepOneContainer() async throws {
        let container = try makeContainer()
        var attempts = 0
        let startup = LibraryStartupService {
            attempts += 1
            return container
        }

        let first = Task { await startup.open() }
        let second = Task { await startup.open() }
        await first.value
        await second.value
        await startup.open()

        XCTAssertEqual(attempts, 1)
        XCTAssertTrue(startup.modelContainer === container)
    }

    func testSafariRequestsWaitThroughFailureAndResumeOnceAfterRetry() async throws {
        let container = try makeContainer()
        var attempts = 0
        let startup = LibraryStartupService {
            attempts += 1
            if attempts == 1 {
                throw CocoaError(.fileReadNoPermission)
            }

            return container
        }

        var capturedURLs: [URL] = []
        let requests = SafariRequestService { url, context, _ in
            XCTAssertTrue(context === container.mainContext)
            capturedURLs.append(url)
            return nil
        }

        let delegate = WebSnapshotAppDelegate(startup, safariRequests: requests)
        defer {
            delegate.applicationWillTerminate(Notification(name: NSApplication.willTerminateNotification))
            requests.cancel()
        }

        let first = try makeRequest("https://example.com/first")
        let second = try makeRequest("https://example.com/second")
        delegate.application(NSApplication.shared, open: [first.openURL])
        XCTAssertEqual(requests.state.pending, [first])
        XCTAssertTrue(capturedURLs.isEmpty)

        await delegate.openLibrary()
        delegate.application(NSApplication.shared, open: [second.openURL])
        XCTAssertEqual(requests.state.pending, [first, second])
        XCTAssertTrue(capturedURLs.isEmpty)

        await delegate.openLibrary()
        try await waitUntil { requests.state.pending.isEmpty && requests.state.current == nil }
        await delegate.openLibrary()

        XCTAssertEqual(attempts, 2)
        XCTAssertEqual(capturedURLs, [first.url, second.url])
        XCTAssertNil(requests.state.appError)

        let third = try makeRequest("https://example.com/third")
        delegate.application(NSApplication.shared, open: [third.openURL])
        try await waitUntil { requests.state.pending.isEmpty && requests.state.current == nil }
        XCTAssertEqual(capturedURLs, [first.url, second.url, third.url])
    }

    private func makeContainer(_ configuration: ModelConfiguration = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)) throws -> ModelContainer {
        try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self, configurations: configuration)
    }

    private func makeRequest(_ address: String) throws -> SafariCaptureRequest {
        try SafariCaptureRequest(id: UUID(), url: XCTUnwrap(URL(string: address)))
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(2)
        while !condition() && Date() < deadline {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertTrue(condition(), "Timed out waiting for queued Safari saves")
    }
}
