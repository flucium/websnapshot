import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
                .frame(minWidth: 730, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
        .modelContainer(for: [
            AppearanceSettings.self,
            PDFFile.self,
            PDFTag.self,
        ])
    }
}
