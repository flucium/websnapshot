import SwiftUI
import SwiftData


struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Query private var appearanceSettings: [AppearanceSettings]

    @StateObject private var homeViewState = HomeViewState()

    private var appearance: AppearanceSettings.Appearance {
        appearance(appearanceSettings)
    }

    private var preferredColorScheme: ColorScheme? {
        switch appearance {
        case .light:
            .light
        case .dark:
            .dark
        case .system:
            nil
        }
    }
    
    private func appearance(_ settings: [AppearanceSettings]) -> AppearanceSettings.Appearance {
        settings.first?.appearance ?? .system
    }
    
    private func updateApplicationAppearance(for appearance: AppearanceSettings.Appearance) {
#if os(macOS)
        ApplicationAppearanceUpdater.update(for: appearance, colorScheme: colorScheme)
#endif
    }
    
    @ViewBuilder
    private func detail(_ destination: NavigationDestination?) -> some View {
        switch destination {
        case .single:
            SingleView()
        case .directory:
            DirectoryView()
        case .settings:
            SettingsView()
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func applyingPreferredColorScheme<Content: View>(
        to content: Content
    ) -> some View {
#if os(macOS)
        content
#else
        content.preferredColorScheme(preferredColorScheme)
#endif
    }

    var body: some View {
        applyingPreferredColorScheme(
            to: NavigationSplitView {
                List(selection: $homeViewState.destination) {
                    NavigationLink(value: NavigationDestination.single) {
                        Label("Single", systemImage: "magnifyingglass")
                    }

                    NavigationLink(value: NavigationDestination.directory) {
                        Label("Directory", systemImage: "folder")
                    }

                    NavigationLink(value: NavigationDestination.settings) {
                        Label("Settings", systemImage: "gear")
                    }
                }
            } detail: {
                detail(homeViewState.destination)
            }
        )
        .onAppear {
            updateApplicationAppearance(for: appearance)
        }
        .onChange(of: appearance) {
            _, changedAppearance in
            updateApplicationAppearance(for: changedAppearance)
        }
        .onChange(of: colorScheme) {
            updateApplicationAppearance(for: appearance)
        }
    }
}

#Preview {
    HomeView()
}
