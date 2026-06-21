import Combine

enum NavigationDestination: Hashable {
    case single
    case directory
    case settings
}

final class HomeViewState: ObservableObject {
    @Published var destination: NavigationDestination? = .single
}
