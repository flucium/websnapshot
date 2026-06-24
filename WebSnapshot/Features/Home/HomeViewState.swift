import Combine

enum NavigationDestination: Hashable {
    case fetch
    case library
    case settings
}

final class HomeViewState: ObservableObject {
    @Published var destination: NavigationDestination? = .fetch
}
