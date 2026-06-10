import SwiftUI
import SwiftData

private enum NavigationDestination: Hashable {
    case single
    case directory
    case settings
}


struct HomeView: View {
    @Environment(\.colorScheme) private var colorScheme

    @Query private var appearanceSettings: [AppearanceSettings]

    @State private var destination: NavigationDestination? = .single
    
    private var appearance: AppearanceSettings.Appearance {
        appearance(appearanceSettings)
    }
    
    private func appearance(_ settings: [AppearanceSettings]) -> AppearanceSettings.Appearance {
        settings.first?.appearance ?? .system
    }
    
    private func appearance(_ selectedAppearance: AppearanceSettings.Appearance) {
        let appearance = nsAppearance(selectedAppearance)

        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
     
            window.contentView?.appearance = appearance
        }

        updateApplicationIcon(for: selectedAppearance)
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
            NSBezierPath(roundedRect: iconRect, xRadius: 23, yRadius: 23).addClip()
            sourceImage.draw(in: iconRect)
            return true
        }

        NSApp.applicationIconImage = applicationIcon
    }
    
    
    private func nsAppearance(_ appearance: AppearanceSettings.Appearance) -> NSAppearance? {
        switch appearance {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            return nil
        }
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
    
    var body: some View {
        NavigationSplitView{
            List(selection: $destination) {
                NavigationLink(value: NavigationDestination.single,label: {
                    Label("Single", systemImage: "magnifyingglass")
                })
                NavigationLink(value: NavigationDestination.directory,label: {
                    Label("Directory", systemImage: "folder")
                })
                NavigationLink(value: NavigationDestination.settings,label: {
                    Label("Settings", systemImage: "gear")
                })
            }
        } detail: {
            detail(destination)
        }
        .onAppear {
            appearance(appearance)
        }
        .onChange(of: appearance) {
            _, changedAppearance in
            appearance(changedAppearance)
        }
        .onChange(of: colorScheme) {
            updateApplicationIcon(for: appearance)
        }
    }
}

#Preview {
    HomeView()
}
