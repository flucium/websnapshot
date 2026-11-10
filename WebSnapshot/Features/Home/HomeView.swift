import SwiftUI
import SwiftData
import AppKit


struct HomeView: View {
    @StateObject private var homeViewState = HomeViewState()
    
    @EnvironmentObject private var librarySyncService: LibrarySyncService
    
    @Query private var appearanceSettings: [AppearanceSettings]
    
    private var librarySyncState: LibrarySyncState { librarySyncService.state }

    private var appearance: AppearanceSettings.Appearance {
        appearance(appearanceSettings)
    }

    private func appearance(_ settings: [AppearanceSettings]) -> AppearanceSettings.Appearance {
        settings.first?.appearance ?? .system
    }

    private func updateApplicationAppearance(_ appearance: AppearanceSettings.Appearance) {
        let applicationAppearance: NSAppearance? = switch appearance {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .system:
            nil
        }

        NSApp.appearance = applicationAppearance

        for window in NSApp.windows {
            window.appearance = applicationAppearance
            window.contentView?.appearance = applicationAppearance
        }
    }
    
    @ViewBuilder
    private func detail(_ destination: NavigationDestination?) -> some View {
        switch destination {
        case .fetch:
            FetchView()
        case .library:
            LibraryView()
        case .settings:
            SettingsView()
        default:
            EmptyView()
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $homeViewState.destination) {
                NavigationLink(value: NavigationDestination.fetch) {
                    Label("Fetch", systemImage: "magnifyingglass")
                }

                NavigationLink(value: NavigationDestination.library) {
                    Label("Library", systemImage: "folder")
                }

                NavigationLink(value: NavigationDestination.settings) {
                    Label("Settings", systemImage: "gear")
                }
            }
        } detail: {
            detail(homeViewState.destination)
        }
        .onAppear {
            updateApplicationAppearance(appearance)
        }
        .disabled(librarySyncState.isSwitching)
        .onChange(of: appearance) {
            _, changedAppearance in
            updateApplicationAppearance(changedAppearance)
        }
    }
}

#Preview {
    let librarySyncService = LibrarySyncService()
    let contentService = LibraryContentService(librarySyncService)

    HomeView()
        .environmentObject(contentService)
        .environmentObject(librarySyncService)
}
