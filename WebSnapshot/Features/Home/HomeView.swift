import SwiftUI
import SwiftData
import AppKit


struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme

    @StateObject private var homeViewState = HomeViewState()
    
    @Query private var appearanceSettings: [AppearanceSettings]


    private var appearance: AppearanceSettings.Appearance {
        appearance(appearanceSettings)
    }

    private func appearance(_ settings: [AppearanceSettings]) -> AppearanceSettings.Appearance {
        settings.first?.appearance ?? .system
    }

    private func updateApplicationAppearance(for appearance: AppearanceSettings.Appearance) {
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

        updateApplicationIcon(for: appearance)
    }

    private func updateApplicationIcon(for appearance: AppearanceSettings.Appearance) {
        let usesDarkIcon = switch appearance {
        case .light:
            false
        case .dark:
            true
        case .system:
            colorScheme == .dark
        }

        let sourceImage: NSImage = usesDarkIcon ? .appIconDark : .appIconLight
        
        let iconSize = NSSize(width: 128, height: 128)

        let applicationIcon = NSImage(size: iconSize, flipped: false) { _ in
            let iconRect = NSRect(origin: .zero, size: iconSize).insetBy(dx: 12, dy: 12)

            NSBezierPath(roundedRect: iconRect,xRadius: 23,yRadius: 23).addClip()

            sourceImage.draw(in: iconRect)

            return true
        }

        NSApp.applicationIconImage = applicationIcon
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
