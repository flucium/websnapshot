import Foundation
import Darwin
import Combine
import SwiftData

@MainActor
final class LibraryPDFFileMonitor: ObservableObject {
    struct Change {
        let fileID: PersistentIdentifier
        let url: URL
        let wasDeleted: Bool
    }

    private var monitors: [PersistentIdentifier: PDFFileMonitor] = [:]

    func sync(_ pdfFiles: [PDFFile],_ onMissing: @escaping (Change) -> Void) {
        let fileIDs = Set(pdfFiles.map(\.persistentModelID))

        for key in Array(monitors.keys) where fileIDs.contains(key) == false {
            monitors[key]?.stop()
            monitors[key] = nil
        }

        for pdfFile in pdfFiles {
            let key = pdfFile.persistentModelID

            guard pdfFile.availability == .available, let url = try? pdfFile.resolveURL() else {
                continue
            }

            if let monitor = monitors[key], monitor.url == url {
                _ = monitor.start()
                continue
            }

            monitors[key]?.stop()
            let monitor = PDFFileMonitor(url) { missingURL, wasDeleted in
                Task { @MainActor in
                    onMissing(Change(fileID: key, url: missingURL, wasDeleted: wasDeleted))
                }
            }

            monitors[key] = monitor
            if monitor.start() == false && FileManager.default.fileExists(atPath: url.path) {
                AppLogger.recordDiagnostic(
                    "The file monitor could not be started.",
                    "Monitor PDF",
                    url
                )
            }
        }
    }

    func stop() {
        for monitor in monitors.values {
            monitor.stop()
        }

        monitors.removeAll()
    }

}

private final class PDFFileMonitor {
    let url: URL
    private let onMissing: (URL, Bool) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var isAccessingSecurityScopedResource = false

    init(_ url: URL, _ onMissing: @escaping (URL, Bool) -> Void) {
        self.url = url
        self.onMissing = onMissing
    }

    deinit {
        stop()
    }

    func start() -> Bool {
        guard source == nil else {
            return true
        }

        isAccessingSecurityScopedResource = url.startAccessingSecurityScopedResource()

        guard FileManager.default.fileExists(atPath: url.path) else {
            stopAccessingSecurityScopedResource()
            onMissing(url, false)
            return false
        }

        fileDescriptor = open(url.path, O_EVTONLY)

        guard fileDescriptor >= 0 else {
            stopAccessingSecurityScopedResource()

            if FileManager.default.fileExists(atPath: url.path) == false {
                onMissing(url, false)
            }

            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.delete, .rename, .revoke],
            queue: .main
        )

        source.setEventHandler { [weak self, weak source] in
            let wasDeleted = source?.data.contains(.delete) == true
            Task { @MainActor in
                self?.handleFileEvent(wasDeleted: wasDeleted)
            }
        }
        let descriptor = fileDescriptor
        source.setCancelHandler {
            close(descriptor)
        }

        self.source = source
        source.resume()

        return true
    }

    func stop() {
        source?.cancel()
        source = nil

        fileDescriptor = -1

        stopAccessingSecurityScopedResource()
    }

    private func handleFileEvent(wasDeleted: Bool) {
        guard FileManager.default.fileExists( atPath: url.path) == false else {
            return
        }

        onMissing(url, wasDeleted)
        stop()
    }

    private func stopAccessingSecurityScopedResource() {
        guard isAccessingSecurityScopedResource else {
            return
        }

        url.stopAccessingSecurityScopedResource()
        isAccessingSecurityScopedResource = false
    }
}
