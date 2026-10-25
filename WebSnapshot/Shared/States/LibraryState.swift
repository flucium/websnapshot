@MainActor
struct LibrarySyncState {
    var isSwitching = false

    var lastError: AppError?
}

@MainActor
struct LibraryContentState {
    var isIndexing = false

    var isRefreshingCache = false

    var pendingCount = 0

    var failedCount = 0

    var cacheRefreshResult: CacheRefreshResult?

    struct CacheRefreshResult {
        let refreshedCount: Int
        let removedCount: Int
        let unavailableCount: Int
    }
}
