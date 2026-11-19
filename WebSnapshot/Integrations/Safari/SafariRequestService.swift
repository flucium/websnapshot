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

    @Published private(set) var safariRequestState = SafariRequestState()
    
    private var failedRequest: SafariCaptureRequest?
    
    private var receivedIDs: Set<UUID> = []
    
    private var receivedOrder: [UUID] = []
    
    private var task: Task<Void, Never>?
    
    private let capture: CaptureWithProgress
    
    typealias Capture = @MainActor (URL, ModelContext, (WebPage) -> Void) async throws -> URL?

    typealias CaptureWithProgress = @MainActor (URL, ModelContext, (WebPage) -> Void, (WebPDFExportState) -> Void) async throws -> URL?

    var handleFailure: ((AppError) -> FailureAction)?
    
    var canRetry: Bool {
        failedRequest != nil && safariRequestState.current == nil
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
            
            safariRequestState.pending.append(request)
            
        } catch {
            safariRequestState.appError = .invalidURL(error.localizedDescription)
        }
        
    }

    func startProcessing(_ modelContext: ModelContext) {
        guard task == nil, !safariRequestState.pending.isEmpty, safariRequestState.appError == nil else {
            return
        }
        
        task = Task {
            defer {
            
                task = nil
                
                startProcessing(modelContext)
            }
            
            while !state.pending.isEmpty && !Task.isCancelled {
                
                let request = safariRequestState.pending.removeFirst()
                
                safariRequestState.current = request
                
                safariRequestState.savedURL = nil

                safariRequestState.exportState = nil

                safariRequestState.isCancelling = false
                
                failedRequest = nil
                
                safariRequestState.status = "Reloading URL without Safari sign-in or form entries…"
                
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

                    safariRequestState.savedURL = savedURL
                    
                    safariRequestState.status = safariRequestState.savedURL == nil ? "Save cancelled." : "PDF saved from the reloaded URL."
                    
                } catch {
                    if !Task.isCancelled, let error = AppError.presentable(error) {
                    
                        safariRequestState.appError = error
                        
                        failedRequest = request
                        
                        safariRequestState.status = "PDF could not be saved."
                        
                        AppLogger.record(error, "Save webpage from Safari", request.url)

                        if let handleFailure {
                            
                            let action = handleFailure(error)
                            
                            if action == .retry, !Task.isCancelled {
                                safariRequestState.pending.insert(request, at: 0)
                            }
                            
                            safariRequestState.appError = nil
                            
                            failedRequest = nil
                        }
                        
                    } else {
                        safariRequestState.status = "Save cancelled."
                    }
                }
                
                if Task.isCancelled {
                    safariRequestState.status = "Save cancelled."
                }

                safariRequestState.current = nil

                safariRequestState.webPage = nil

                safariRequestState.exportState = nil

                safariRequestState.isCancelling = false
                
                if safariRequestState.appError != nil {
                    break
                }
            }
        }
    }

    func retry(_ modelContext: ModelContext) {
        
        guard let failedRequest, safariRequestState.current == nil else {
            return
        }
        
        safariRequestState.pending.insert(failedRequest, at: 0)
        
        self.failedRequest = nil
        
        safariRequestState.appError = nil
        
        startProcessing(modelContext)
    }

    func dismissError(_ modelContext: ModelContext) {
        safariRequestState.appError = nil
        
        
        failedRequest = nil
        
        startProcessing(modelContext)
    }

    func cancel() {
        
        safariRequestState.pending.removeAll()
        
        task?.cancel()

        failedRequest = nil

        safariRequestState.appError = nil

        safariRequestState.isCancelling = task != nil

        safariRequestState.status = task == nil ? "Save cancelled." : "Cancelling…"
        
        safariRequestState.webPage?.stopLoading()
    }
}
