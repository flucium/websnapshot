import Foundation
import Combine
import SwiftData
import WebKit

@MainActor
final class SafariRequestService: ObservableObject {
    enum FailureAction {
        case retry
        case skip
    }

    @Published private(set) var state = SafariRequestState()
    
    private var failedRequest: SafariCaptureRequest?
    
    private var receivedIDs: Set<UUID> = []
    
    private var receivedOrder: [UUID] = []
    
    private var task: Task<Void, Never>?
    
    private let capture: Capture
    
    typealias Capture = @MainActor (URL, ModelContext, (WebPage) -> Void) async throws -> URL?

    var handleFailure: ((AppError) -> FailureAction)?
    var canRetry: Bool {
        failedRequest != nil && state.current == nil
    }

    init(_ capture: @escaping Capture) {
        self.capture = capture
    }

    func receive(_ url: URL) {
        do {
            let request = try SafariCaptureRequest(openURL: url)
            
            guard receivedIDs.insert(request.id).inserted else {
                return
            }
            
            receivedOrder.append(request.id)
            
            if receivedOrder.count > 256 {
                receivedIDs.remove(receivedOrder.removeFirst())
            }
            
            state.pending.append(request)
            
        } catch {
            state.appError = .invalidURL(error.localizedDescription)
        }
        
    }

    func startProcessing(_ modelContext: ModelContext) {
        guard task == nil, !state.pending.isEmpty, state.appError == nil else {
            return
        }
        
        task = Task {
            defer {
            
                task = nil
                
                startProcessing(modelContext)
            }
            
            while !state.pending.isEmpty && !Task.isCancelled {
                
                let request = state.pending.removeFirst()
                
                state.current = request
                
                state.savedURL = nil
                
                failedRequest = nil
                
                state.status = "Loading and saving webpage…"
                
                do {
                    state.savedURL = try await capture(request.url, modelContext) {
                        page in
                        self.state.webPage = page
                    }
                    
                    state.status = state.savedURL == nil ? "Save cancelled." : "PDF saved."
                    
                } catch {
                    if let error = AppError.presentable(error) {
                    
                        state.appError = error
                        
                        failedRequest = request
                        
                        state.status = "PDF could not be saved."
                        
                        AppLogger.record(error, "Save webpage from Safari", request.url)

                        if let handleFailure {
                            
                            let action = handleFailure(error)
                            
                            if action == .retry {
                                state.pending.insert(request, at: 0)
                            }
                            
                            state.appError = nil
                            
                            failedRequest = nil
                        }
                        
                    } else {
                        state.status = "Save cancelled."
                    }
                }
                
                state.current = nil
                
                if state.appError != nil {
                    break
                }
            }
        }
    }

    func retry(_ modelContext: ModelContext) {
        
        guard let failedRequest, state.current == nil else {
            return
        }
        
        state.pending.insert(failedRequest, at: 0)
        
        self.failedRequest = nil
        
        state.appError = nil
        
        startProcessing(modelContext)
    }

    func dismissError(_ modelContext: ModelContext) {
        state.appError = nil
        
        
        failedRequest = nil
        
        startProcessing(modelContext)
    }

    func cancel() {
        
        state.pending.removeAll()
        
        task?.cancel()
        
        state.webPage?.stopLoading()
    }
}
