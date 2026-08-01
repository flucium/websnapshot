import Foundation
import Darwin
import Combine

@MainActor
final class LibraryPDFFileMonitor: ObservableObject {
    private var monitors: [String: PDFFileMonitor] = [:]

    func sync(_ pdfFiles: [PDFFile],_ onMissing: @escaping (URL) -> Void) {
        let paths = Set(pdfFiles.map { monitorKey( $0.url) })

        for key in Array(monitors.keys) where paths.contains(key) == false {
            monitors[key]?.stop()
            monitors[key] = nil
        }

        for pdfFile in pdfFiles {
            let url = pdfFile.url
            let key = monitorKey( url)

            guard monitors[key] == nil else {
                continue
            }

            let monitor = PDFFileMonitor( url) { missingURL in
                Task { @MainActor in
                    onMissing(missingURL)
                }
            }

            if monitor.start() {
                monitors[key] = monitor
            } else if FileManager.default.fileExists(atPath: url.path) {
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

    private func monitorKey(_ url: URL) -> String {
        url.standardizedFileURL.path
    }
}

private final class PDFFileMonitor {
    private let url: URL
    private let onMissing: (URL) -> Void

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: CInt = -1
    private var isAccessingSecurityScopedResource = false

    init(_ url: URL, _ onMissing: @escaping (URL) -> Void) {
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
            onMissing(url)
            return false
        }

        fileDescriptor = open(url.path, O_EVTONLY)

        guard fileDescriptor >= 0 else {
            stopAccessingSecurityScopedResource()

            if FileManager.default.fileExists(atPath: url.path) == false {
                onMissing(url)
            }

            return false
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.delete, .rename, .revoke],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.handleFileEvent()
            }
        }

        self.source = source
        source.resume()

        return true
    }

    func stop() {
        source?.cancel()
        source = nil

        if fileDescriptor >= 0 {
            closeFileDescriptor()
        }

        stopAccessingSecurityScopedResource()
    }

    private func handleFileEvent() {
        guard FileManager.default.fileExists( atPath: url.path) == false else {
            return
        }

        onMissing(url)
        stop()
    }

    private func closeFileDescriptor() {
        guard fileDescriptor >= 0 else {
            return
        }

        close(fileDescriptor)
        fileDescriptor = -1
    }

    private func stopAccessingSecurityScopedResource() {
        guard isAccessingSecurityScopedResource else {
            return
        }

        url.stopAccessingSecurityScopedResource()
        isAccessingSecurityScopedResource = false
    }
}
