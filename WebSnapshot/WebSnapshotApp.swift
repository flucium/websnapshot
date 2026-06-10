import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    var body: some Scene {
        WindowGroup {
            HomeView()
        }.modelContainer(for: [
            AppearanceSettings.self,
            PDFFile.self,
        ])
    }
}
