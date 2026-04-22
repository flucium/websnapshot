import SwiftUI
import SwiftData

private enum NavigationDestination: Hashable {
    case single
    case multiple
    case directory
    case settings
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    
    @State private var destination: NavigationDestination? = .single
    
    @ViewBuilder
    private func detail(_ destination: NavigationDestination?) -> some View {
        switch destination {
        case .single:
            SingleView()
        case .multiple:
            EmptyView()
        case .directory:
            DirectoryView()
        case .settings:
            EmptyView()
        default:
            EmptyView()
        }
    }
    
    var body: some View {
        NavigationSplitView {
            List(selection: $destination) {
                NavigationLink(value: NavigationDestination.single) {
                    Label("Single", systemImage: "magnifyingglass")
                }
                NavigationLink(value: NavigationDestination.multiple) {
                    Label("Multiple", systemImage: "magnifyingglass")
                }
                NavigationLink(value: NavigationDestination.directory) {
                        
                    Label("Directory", systemImage: "folder")
                }
                NavigationLink(value: NavigationDestination.settings){
                    Label("Settings", systemImage: "gear")
                }
            }
        } detail: {
            detail(destination)
        }
    }
}

#Preview {
    HomeView()
}
