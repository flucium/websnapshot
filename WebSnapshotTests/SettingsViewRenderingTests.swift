import AppKit
import OSLog
import SwiftData
import SwiftUI
import XCTest
@testable import WebSnapshot

@MainActor
final class SettingsViewRenderingTests: XCTestCase {
    func testOpeningAndChangingSettingsDoesNotPublishDuringViewUpdates() async throws {
        let startedAt = Date()
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(
            for: AppearanceSettings.self,
            StorageSettings.self,
            configurations: configuration
        )
        container.mainContext.autosaveEnabled = false
        container.mainContext.insert(AppearanceSettings(.dark))
        container.mainContext.insert(StorageSettings(.fixed))
        try container.mainContext.save()

        let hostingView = NSHostingView(rootView: SettingsView().modelContainer(container))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        window.orderFront(nil)
        defer { window.close() }

        try await settle(hostingView)
        let appearanceControl = try findSegments(["Light", "Dark", "System"], in: hostingView)
        let storageControl = try findSegments(["Fixed", "Flexibility"], in: hostingView)

        // Rendering a saved preference must not replace it with @State defaults.
        XCTAssertEqual(selectedLabel(in: appearanceControl), "Dark")
        XCTAssertEqual(selectedLabel(in: storageControl), "Fixed")
        try assertSavedSettings(container, appearance: .dark, storage: .fixed)

        for appearance in [AppearanceSettings.Appearance.light, .system, .dark] {
            let control = try findSegments(["Light", "Dark", "System"], in: hostingView)
            try select(AppearanceSettingsService.title(appearance), in: control)
            try await settle(hostingView)
            XCTAssertEqual(selectedLabel(in: control), AppearanceSettingsService.title(appearance))
            try assertSavedSettings(container, appearance: appearance, storage: .fixed)
        }

        for storage in [StorageSettings.Storage.flexibility, .fixed] {
            let control = try findSegments(["Fixed", "Flexibility"], in: hostingView)
            try select(StorageSettingsService.title(storage), in: control)
            try await settle(hostingView)
            XCTAssertEqual(selectedLabel(in: control), StorageSettingsService.title(storage))
            try assertSavedSettings(container, appearance: .dark, storage: storage)
        }

        window.orderOut(nil)
        try await assertNoViewUpdateWarnings(since: startedAt)
    }

    private func settle(_ view: NSView) async throws {
        // Yield to SwiftUI/AppKit's run loop instead of blocking the main actor.
        for _ in 0..<10 {
            view.layoutSubtreeIfNeeded()
            view.displayIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    private func findSegments(_ labels: [String], in view: NSView) throws -> NSSegmentedControl {
        let matches = descendants(of: view).compactMap { $0 as? NSSegmentedControl }
            .filter { control in
                (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" } == labels
            }
        if matches.count != 1 {
            let hierarchy = descendants(of: view).map { child in
                let labels = (child as? NSSegmentedControl).map { control in
                    (0..<control.segmentCount).map { control.label(forSegment: $0) ?? "" }
                } ?? []
                return "\(type(of: child)): \(labels)"
            }.joined(separator: "\n")
            let attachment = XCTAttachment(string: hierarchy)
            attachment.name = "Settings view AppKit hierarchy"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertEqual(matches.count, 1, "Expected one real segmented control with labels \(labels)")
        return try XCTUnwrap(matches.first)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }

    private func select(_ label: String, in control: NSSegmentedControl) throws {
        let segment = try XCTUnwrap((0..<control.segmentCount).first {
            control.label(forSegment: $0) == label
        })
        XCTAssertTrue(control.isEnabled)
        control.selectedSegment = segment
        let action = try XCTUnwrap(control.action, "The picker must have a live AppKit action")
        XCTAssertTrue(control.sendAction(action, to: control.target), "Picker action was not delivered")
    }

    private func selectedLabel(in control: NSSegmentedControl) -> String? {
        guard control.selectedSegment >= 0 else { return nil }
        return control.label(forSegment: control.selectedSegment)
    }

    private func assertSavedSettings(
        _ container: ModelContainer,
        appearance: AppearanceSettings.Appearance,
        storage: StorageSettings.Storage,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        // A separate context proves the change was saved, not just mutated in memory.
        let context = ModelContext(container)
        let appearances = try context.fetch(FetchDescriptor<AppearanceSettings>())
        let storages = try context.fetch(FetchDescriptor<StorageSettings>())
        XCTAssertEqual(appearances.count, 1, file: file, line: line)
        XCTAssertEqual(storages.count, 1, file: file, line: line)
        XCTAssertEqual(appearances.first?.appearance, appearance, file: file, line: line)
        XCTAssertEqual(storages.first?.storage, storage, file: file, line: line)
    }

    private func assertNoViewUpdateWarnings(since startedAt: Date) async throws {
        let marker = UUID().uuidString
        let logger = Logger(subsystem: "WebSnapshotTests", category: "SettingsViewRendering")
        logger.error("Settings view rendering finished: \(marker, privacy: .public)")

        // A store is a snapshot. Reopen it until our end marker is visible so an
        // unavailable or not-yet-flushed log cannot produce a false passing test.
        for _ in 0..<20 {
            try await Task.sleep(for: .milliseconds(250))
            let store = try OSLogStore(scope: .currentProcessIdentifier)
            let entries = try store.getEntries(at: store.position(date: startedAt))
                .compactMap { $0 as? OSLogEntryLog }
            guard entries.contains(where: { $0.composedMessage.contains(marker) }) else {
                continue
            }

            let warnings = entries.filter {
                $0.composedMessage.contains("Publishing changes from within view updates")
                    || $0.composedMessage.contains("Modifying state during view update")
            }.map(\.composedMessage)
            let attachment = XCTAttachment(string: entries.map {
                "\($0.date) [\($0.subsystem):\($0.category)] \($0.composedMessage)"
            }.joined(separator: "\n"))
            attachment.name = "Settings view runtime log"
            attachment.lifetime = .keepAlways
            add(attachment)
            XCTAssertTrue(warnings.isEmpty, warnings.joined(separator: "\n"))
            return
        }

        XCTFail("Runtime log verification is unavailable: the test's own OSLog marker was not readable. This run cannot establish that SwiftUI warnings are absent.")
    }
}
