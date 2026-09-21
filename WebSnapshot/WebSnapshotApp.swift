import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    @StateObject private var safariRequests = SafariRequestService(capture: WebCaptureService.capture)
    private let sharedModelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self)
        } catch {
            fatalError("Could not open the WebSnapshot library: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .frame(minWidth: 730, minHeight: 400)
                .modifier(SafariRequestReceiver())
                .environmentObject(safariRequests)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(sharedModelContainer)

        Window("Save from Safari", id: "safari-capture") {
            SafariCaptureView()
                .modifier(SafariRequestReceiver())
                .environmentObject(safariRequests)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(sharedModelContainer)
    }
}

private struct SafariRequestReceiver: ViewModifier {
    @Environment(\.openWindow) private var openWindow
    
    @EnvironmentObject private var requests: SafariRequestService

    func body(content: Content) -> some View {
        content.onOpenURL { url in
            requests.receive(url)
            openWindow(id: "safari-capture")
        }
    }
}
