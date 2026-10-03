import Foundation
import Combine

@MainActor
final class SettingsViewState:ObservableObject{
    @Published var appError:AppError?
    @Published var errorTitle = "Setting Could Not Be Saved"
    @Published var isRefreshingCache = false
    @Published var cacheRefreshResult: CacheRefreshResult?
    
    var cacheRefreshTask: Task<Void, Never>?

    struct CacheRefreshResult {
        let refreshedCount: Int
        let removedCount: Int
        let unavailableCount: Int
    }
    
}
