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
