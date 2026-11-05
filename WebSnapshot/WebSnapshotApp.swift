import AppKit
import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    @NSApplicationDelegateAdaptor(WebSnapshotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WebSnapshotRootView(appDelegate: appDelegate, startup: appDelegate.startup)
                .frame(minWidth: 980, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
    }
}

private struct WebSnapshotRootView: View {
    let appDelegate: WebSnapshotAppDelegate

    @ObservedObject var startup: LibraryStartupService

    var body: some View {
        if let modelContainer = startup.modelContainer {
            HomeView()
                .environmentObject(appDelegate.content)
                .environmentObject(appDelegate.sync)
                .modelContainer(modelContainer)
        } else {
            DatabaseRecoveryView(startup: startup) {
                Task {
                    await appDelegate.openLibrary()
                }
            }
        }
    }
}

@MainActor
final class WebSnapshotAppDelegate: NSObject, NSApplicationDelegate {
    let startup: LibraryStartupService
    let sync: LibrarySyncService
    let content: LibraryContentService
    let safariRequests: SafariRequestService

    private var appearanceObservation: NSKeyValueObservation?
    
    private var syncTask: Task<Void, Never>?
    
    override convenience init() {
        self.init(LibraryStartupService())
    }

    init(_ startup: LibraryStartupService, safariRequests: SafariRequestService? = nil) {
        self.startup = startup
        
        let sync = LibrarySyncService()
        
        self.sync = sync
        
        content = LibraryContentService(sync: sync)
        
        self.safariRequests = safariRequests ?? SafariRequestService {
            
            url, context, onStart in
            
            try await WebCaptureService.capture(url, context, sync: sync, chooseDestination: { name in
                prepareForSafariDialog()
                
                return savePanel(name)
                
            }, onStart)
        }

        super.init()
    }
    

    func applicationDidFinishLaunching(_ notification: Notification) {
       
        Task {
            await openLibrary()
        }
        
        appearanceObservation = NSApp.observe(\.appearance, options: [.initial, .new]) {
            [weak self] _, _ in
            
            Task {
                @MainActor [weak self] in
                
                self?.updateApplicationIcon()
                
            }
            
        }
        
    }

    func openLibrary() async {
        await startup.open()

        guard let modelContainer = startup.modelContainer else {
            return
        }

        if syncTask == nil {
            syncTask = Task {
                @MainActor in

                while !Task.isCancelled {
                    await sync.refresh(modelContainer.mainContext)

                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        break
                    }
                }
            }
        }

        safariRequests.startProcessing(modelContainer.mainContext)
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTask?.cancel()
    }

   

    func application(_ application: NSApplication, open urls: [URL]) {
        
        let requests = safariRequests
        
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
        
        if let modelContainer = startup.modelContainer {
            requests.startProcessing(modelContainer.mainContext)
        }
    }
    
    private func updateApplicationIcon() {
        
        guard let applicationAppearance = NSApp.appearance else {
            NSApp.applicationIconImage = nil
            return
        }

        let usesDarkIcon = applicationAppearance.bestMatch( from: [.aqua, .darkAqua]) == .darkAqua
        
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
}
