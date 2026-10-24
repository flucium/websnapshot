import AppKit
import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    @NSApplicationDelegateAdaptor(WebSnapshotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(appDelegate.content)
                .environmentObject(appDelegate.sync)
                .frame(minWidth: 980, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(appDelegate.modelContainer)
    }
}

@MainActor
final class WebSnapshotAppDelegate: NSObject, NSApplicationDelegate {
    let modelContainer: ModelContainer
    let sync: LibrarySyncService
    let content: LibraryContentService
    let safariRequests: SafariRequestService

    override init() {
        
        let sync = LibrarySyncService()
        
        self.sync = sync
        
        content = LibraryContentService(sync: sync)
        
        safariRequests = SafariRequestService {
            
            url, context, onStart in
            
            try await WebCaptureService.capture(url, context, sync: sync, chooseDestination: { name in
                prepareForSafariDialog()
                
                return savePanel(name)
                
            }, onStart)
        }

        do {
            modelContainer = try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
        } catch {
            fatalError("Could not open the WebSnapshot library: \(error)")
        }
        super.init()
    }
    
    private var appearanceObservation: NSKeyValueObservation?
    
    private var syncTask: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
       
        syncTask = Task {
            @MainActor in
            
            while !Task.isCancelled {
                
                await sync.refresh(modelContainer.mainContext)
                
                do {
                    try await Task.sleep(for: .seconds(2))
                }catch {
                    break
                }
            
            }
            
            
        }
        
        appearanceObservation = NSApp.observe(\.appearance, options: [.initial, .new]) {
            [weak self] _, _ in
            
            Task {
                @MainActor [weak self] in
                
                self?.updateApplicationIcon()
                
            }
            
        }
        
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTask?.cancel()
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
        
        requests.startProcessing(modelContainer.mainContext)
    }
}
