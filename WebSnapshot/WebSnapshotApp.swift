import AppKit
import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    @NSApplicationDelegateAdaptor(WebSnapshotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .frame(minWidth: 980, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(SafariAppServices.modelContainer)
    }
}

@MainActor
private enum SafariAppServices {
    static let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self)
        } catch {
            fatalError("Could not open the WebSnapshot library: \(error)")
        }
    }()

    static let safariRequests = SafariRequestService(capture: WebCaptureService.capture)
}

@MainActor
final class WebSnapshotAppDelegate: NSObject, NSApplicationDelegate {
    private var effectiveAppearanceObservation: NSKeyValueObservation?

    func applicationDidFinishLaunching(_ notification: Notification) {
        
        effectiveAppearanceObservation = NSApp.observe(\.effectiveAppearance, options: [.initial, .new]) { [weak self] _, _ in
            
            Task { @MainActor [weak self] in
                self?.updateApplicationIcon()
            }
            
        }
        
    }

    private func updateApplicationIcon() {
        let usesDarkIcon = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        
        let sourceImage: NSImage = usesDarkIcon ? .appIconDark : .appIconLight
        
        let iconSize = NSSize(width: 128, height: 128)

        let applicationIcon = NSImage(size: iconSize, flipped: false) { _ in
            
            let iconRect = NSRect(origin: .zero, size: iconSize).insetBy(dx: 12, dy: 12)

            NSBezierPath(roundedRect: iconRect, xRadius: 23, yRadius: 23).addClip()
            
            sourceImage.draw(in: iconRect)

            return true
            
        }
        

        NSApp.applicationIconImage = applicationIcon
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        
        let requests = SafariAppServices.safariRequests
        
        requests.handleFailure = {
            
            error in
        
            prepareForSafariDialog()
            
            let alert = NSAlert()
            
            alert.messageText = "Webpage Could Not Be Saved"
            
            alert.informativeText = error.userMessage
            
            alert.alertStyle = .warning
            
            alert.addButton(withTitle: "Retry")
            
            alert.addButton(withTitle: "Skip")
            
            return alert.runModal() == .alertFirstButtonReturn ? .retry : .skip
        }
        

        for url in urls {
            guard (try? SafariCaptureRequest(openURL: url)) != nil else {
                continue
            }
            
            requests.receive(url)
        }
        
        requests.startProcessing(SafariAppServices.modelContainer.mainContext)
    }
}
