import SwiftUI
import SwiftData
import AppKit

private enum NavigationDestination: Hashable {
    case single
//    case multiple
    case directory
    case settings
}

struct HomeView: View {
    @Query private var settings: [GeneralSettings]
    
    @State private var destination: NavigationDestination? = .single
    
    @ViewBuilder
    private func detail(_ destination: NavigationDestination?) -> some View {
        switch destination {
        case .single:
            SingleView()
//        case .multiple:
//            EmptyView()
        case .directory:
            DirectoryView()
        case .settings:
            SettingsView()
        default:
            EmptyView()
        }
    }

    private var appearance: Appearance {
        SettingsViewService.appearance(settings)
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                NavigationLink(value: NavigationDestination.single,label: {
                    Label("Single", systemImage: "magnifyingglass")
                })
//                NavigationLink(value: NavigationDestination.multiple,label: {
//                    Label("Multiple", systemImage: "magnifyingglass")
//                })
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
            apply(appearance)
        }
        .onChange(of: appearance) {
            _, changedAppearance in
            apply(changedAppearance)
        }
    }

    private func apply(_ appearance: Appearance) {
        let appearance = nsAppearance(appearance)

        NSApp.appearance = appearance

        for window in NSApp.windows {
            window.appearance = appearance
            window.contentView?.appearance = appearance
        }
    }

    private func nsAppearance(_ appearance: Appearance) -> NSAppearance? {
        switch appearance {
        case .light:
            return NSAppearance(named: .aqua)
        case .dark:
            return NSAppearance(named: .darkAqua)
        case .system:
            return nil
        }
    }
}

#Preview {
    HomeView()
        .modelContainer(for: [
            Directory.self,
            DirectoryHistory.self,
            GeneralSettings.self,
        ], inMemory: true)
}
