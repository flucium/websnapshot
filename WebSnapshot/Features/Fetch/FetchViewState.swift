import Combine
import SwiftUI
import WebKit

@MainActor
final class FetchViewState : WebState{
    @Published private(set) var isSaving = false

    @Published private(set) var isCancellingSave = false

    @Published private(set) var exportState: WebPDFExportState?
    
    @Published var failedOperation: Operation?
    
    var loadTask: Task<Void, Never>?
    
    var saveTask: Task<Void, Never>?

    private var loadRequestID: UUID?
    
    private var saveRequestID: UUID?


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
        guard !isSaving, saveTask == nil else {
            return nil
        }
        
        let id = UUID()
        
        saveRequestID = id
        
        isSaving = true

        isCancellingSave = false

        exportState = WebPDFExportState()
        
        return id
    }

    func isCurrentSave(_ id: UUID) -> Bool {
        saveRequestID == id
    }

    func updateExportState(_ progress: WebPDFExportState, _ id: UUID) {
        guard isCurrentSave(id), !isCancellingSave else {
            return
        }

        exportState = progress
    }

    func finishSave(_ id: UUID) {
        guard isCurrentSave(id) else {
            return
        }
        
        saveRequestID = nil
        
        saveTask = nil
        
        isSaving = false

        isCancellingSave = false

        exportState = nil
    }

    func cancelSave() {
        saveTask?.cancel()

        if saveTask != nil {
            isCancellingSave = true
            return
        }
        
        saveRequestID = nil
        
        isSaving = false

        isCancellingSave = false

        exportState = nil
    }

    override func clear() {
        
        cancelLoad()
        
        super.clear()
        
        failedOperation = nil
    }
}
