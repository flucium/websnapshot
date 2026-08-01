import Combine
import SwiftUI

@MainActor
final class FetchViewState : WebState{
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

    @Published var failedOperation: Operation?

    override func clear() {
        super.clear()
        failedOperation = nil
    }
}
