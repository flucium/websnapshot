import Combine

@MainActor
final class LibrarySyncState: ObservableObject {
    @Published var isSwitching = false

    @Published var lastError: AppError?
}
