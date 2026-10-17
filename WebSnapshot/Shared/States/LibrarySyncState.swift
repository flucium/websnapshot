@MainActor
struct LibrarySyncState {
    var isSwitching = false

    var lastError: AppError?
}
