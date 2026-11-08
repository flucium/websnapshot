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
    
    private let capture: CaptureWithProgress
    
    typealias Capture = @MainActor (URL, ModelContext, (WebPage) -> Void) async throws -> URL?

    typealias CaptureWithProgress = @MainActor (URL, ModelContext, (WebPage) -> Void, (WebPDFExportState) -> Void) async throws -> URL?

    var handleFailure: ((AppError) -> FailureAction)?
    var canRetry: Bool {
        failedRequest != nil && state.current == nil
    }

    init(_ capture: @escaping CaptureWithProgress) {
        self.capture = capture
    }

    convenience init(_ capture: @escaping Capture) {
        self.init { url, context, onStart, _ in
            try await capture(url, context, onStart)
        }
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

                state.exportState = nil

                state.isCancelling = false
                
                failedRequest = nil
                
                state.status = "Reloading URL without Safari sign-in or form entries…"
                
                do {
                    let savedURL = try await capture(request.url, modelContext, {
                        page in

                        guard !Task.isCancelled, self.state.current == request else {
                            return
                        }

                        self.state.webPage = page
                    }, {
                        progress in

                        guard !Task.isCancelled, self.state.current == request else {
                            return
                        }

                        self.state.exportState = progress
                        self.state.status = progress.title
                    })

                    try Task.checkCancellation()

                    state.savedURL = savedURL
                    
                    state.status = state.savedURL == nil ? "Save cancelled." : "PDF saved from the reloaded URL."
                    
                } catch {
                    if !Task.isCancelled, let error = AppError.presentable(error) {
                    
                        state.appError = error
                        
                        failedRequest = request
                        
                        state.status = "PDF could not be saved."
                        
                        AppLogger.record(error, "Save webpage from Safari", request.url)

                        if let handleFailure {
                            
                            let action = handleFailure(error)
                            
                            if action == .retry, !Task.isCancelled {
                                state.pending.insert(request, at: 0)
                            }
                            
                            state.appError = nil
                            
                            failedRequest = nil
                        }
                        
                    } else {
                        state.status = "Save cancelled."
                    }
                }
                
                if Task.isCancelled {
                    state.status = "Save cancelled."
                }

                state.current = nil

                state.webPage = nil

                state.exportState = nil

                state.isCancelling = false
                
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

        failedRequest = nil

        state.appError = nil

        state.isCancelling = task != nil

        state.status = task == nil ? "Save cancelled." : "Cancelling…"
        
        state.webPage?.stopLoading()
    }
}
