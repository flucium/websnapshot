import Combine
import SwiftUI
import WebKit

@MainActor
final class FetchViewState : WebState{
    private var loadRequestID: UUID?

    var loadTask: Task<Void, Never>?
    
    @Published var failedOperation: Operation?

    enum Operation: Equatable {
        case load
        case save

        var errorTitle: String {
            switch self {
            case .load:
                "Webpage Could Not Be Loaded"
            case .save:
                "PDF Could Not Be Saved"
            }
        }
    }

    
    func beginLoad() -> UUID {
        cancelLoad()
        let id = UUID()
        loadRequestID = id
        return id
    }

    func isCurrentLoad(_ id: UUID) -> Bool {
        loadRequestID == id
    }

    func finishLoad(_ id: UUID) {
        guard isCurrentLoad(id) else { return }
        loadTask = nil
        loadRequestID = nil
    }

    func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadRequestID = nil
        webPage.stopLoading()
    }

    override func clear() {
        cancelLoad()
        super.clear()
        failedOperation = nil
    }
}
