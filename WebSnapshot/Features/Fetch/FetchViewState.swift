import Combine
import SwiftUI
import WebKit

@MainActor
final class FetchViewState : WebState{
    @Published private(set) var isSaving = false
    
    @Published var failedOperation: Operation?
    
    private var loadRequestID: UUID?
    private var saveRequestID: UUID?

    var loadTask: Task<Void, Never>?
    var saveTask: Task<Void, Never>?


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
        guard isCurrentLoad(id) else {
            return
        }
        
        loadTask = nil
        
        loadRequestID = nil
    }

    func cancelLoad() {
        
        cancelSave()
        
        loadTask?.cancel()
        
        loadTask = nil
        
        loadRequestID = nil
        
        webPage.stopLoading()
    }

    func beginSave() -> UUID? {
        guard !isSaving else {
            return nil
        }
        
        let id = UUID()
        
        saveRequestID = id
        
        isSaving = true
        
        return id
    }

    func isCurrentSave(_ id: UUID) -> Bool {
        saveRequestID == id
    }

    func finishSave(_ id: UUID) {
        guard isCurrentSave(id) else {
            return
        }
        
        saveRequestID = nil
        
        saveTask = nil
        
        isSaving = false
    }

    func cancelSave() {
        saveTask?.cancel()
        
        saveTask = nil
        
        saveRequestID = nil
        
        isSaving = false
    }

    override func clear() {
        
        cancelLoad()
        
        super.clear()
        
        failedOperation = nil
    }
}
