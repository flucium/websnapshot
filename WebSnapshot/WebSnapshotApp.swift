import AppKit
import Combine
import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    @NSApplicationDelegateAdaptor(WebSnapshotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            WebSnapshotRootView(libraryStartupService: appDelegate.libraryStartupService, appDelegate: appDelegate)
                .frame(minWidth: 980, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
    }
}

private struct WebSnapshotRootView: View {
    @ObservedObject var libraryStartupService: LibraryStartupService
    
    let appDelegate: WebSnapshotAppDelegate

    var body: some View {
        if let modelContainer = libraryStartupService.modelContainer {
            HomeView()
                .environmentObject(appDelegate.content)
                .environmentObject(appDelegate.librarySyncService)
                .modelContainer(modelContainer)
        } else {
            DatabaseRecoveryView(libraryStartupService: libraryStartupService) {
                Task {
                    await appDelegate.openLibrary()
                }
            }
        }
    }
}

@MainActor
final class WebSnapshotAppDelegate: NSObject, NSApplicationDelegate {
    let libraryStartupService: LibraryStartupService
    
    let librarySyncService: LibrarySyncService
    
    let content: LibraryContentService
    
    let safariRequests: SafariRequestService

    private var syncTask: Task<Void, Never>?

    private var appearanceObservation: NSKeyValueObservation?

    private var safariProgressObservation: AnyCancellable?

    private var safariProgressWindow: SafariCaptureProgressWindow?

    
    override convenience init() {
        self.init(LibraryStartupService())
    }

    init(_ libraryStartupService: LibraryStartupService, safariRequests: SafariRequestService? = nil) {
        self.libraryStartupService = libraryStartupService
        
        let librarySyncService = LibrarySyncService()
        
        self.librarySyncService = librarySyncService
        
        content = LibraryContentService( librarySyncService)
        
        self.safariRequests = safariRequests ?? SafariRequestService {
            
            url, context, onStart, onProgress in
            
            try await WebCaptureService.capture(url, context, librarySyncService, chooseDestination: { name in
                prepareForSafariDialog()
                
                return savePanel(name)
                
            }, onProgress: onProgress, onStart)
        }

        super.init()
    }
    

    func applicationDidFinishLaunching(_ notification: Notification) {

        safariProgressObservation = safariRequests.$state.sink {
            [weak self] _ in

            Task {
                @MainActor [weak self] in

                self?.updateSafariProgress()
            }
        }
       
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
        await libraryStartupService.open()

        guard let modelContainer = libraryStartupService.modelContainer else {
            return
        }

        if syncTask == nil {
            syncTask = Task {
                @MainActor in

                while !Task.isCancelled {
                    await librarySyncService.refresh(modelContainer.mainContext)

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
        safariProgressObservation?.cancel()
        safariRequests.cancel()
        safariProgressWindow?.window?.orderOut(nil)
    }

    private func updateSafariProgress() {
        if safariRequests.state.current != nil, safariProgressWindow == nil {
            safariProgressWindow = SafariCaptureProgressWindow(safariRequests)
        }

        safariProgressWindow?.update()
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
        
        if let modelContainer = libraryStartupService.modelContainer {
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
    
    deinit {
        appearanceObservation?.invalidate()
        appearanceObservation = nil
    }
}
