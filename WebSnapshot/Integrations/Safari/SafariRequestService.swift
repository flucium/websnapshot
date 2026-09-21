import Combine
import Foundation
import SwiftData
import WebKit

@MainActor
final class SafariRequestService: ObservableObject {
    
    typealias Capture = @MainActor (URL, ModelContext, (WebPage) -> Void) async throws -> URL?
    
    @Published private(set) var pending: [SafariCaptureRequest] = []
    
    @Published private(set) var current: SafariCaptureRequest?
    
    @Published private(set) var webPage: WebPage?
    
    @Published private(set) var savedURL: URL?
    
    @Published private(set) var status = "Ready to save from Safari."
    
    @Published private(set) var appError: AppError?
    
    private var failedRequest: SafariCaptureRequest?
    
    private var receivedIDs: Set<UUID> = []
    
    private var receivedOrder: [UUID] = []
    
    private var task: Task<Void, Never>?
    
    private let capture: Capture

    var canRetry: Bool {
        failedRequest != nil && current == nil
    }

    init(capture: @escaping Capture) {
        self.capture = capture
    }

    func receive(_ url: URL) {
        do {
            let request = try SafariCaptureRequest(openURL: url)
            
            guard receivedIDs.insert(request.id).inserted else { return }
            
            receivedOrder.append(request.id)
            
            if receivedOrder.count > 256 {
                receivedIDs.remove(receivedOrder.removeFirst())
            }
            
            pending.append(request)
            
        } catch {
            appError = .invalidURL(error.localizedDescription)
        }
        
    }

    func startProcessing(_ modelContext: ModelContext) {
        guard task == nil, !pending.isEmpty, appError == nil else {
            return
        }
        
        task = Task {
            defer {
            
                task = nil
                
                startProcessing(modelContext)
            }
            
            while !pending.isEmpty && !Task.isCancelled {
                
                let request = pending.removeFirst()
                
                current = request
                
                savedURL = nil
                
                failedRequest = nil
                
                status = "Loading and saving webpage…"
                
                do {
                    savedURL = try await capture(request.url, modelContext) {
                        page in
                        self.webPage = page
                    }
                    
                    status = savedURL == nil ? "Save cancelled." : "PDF saved."
                    
                } catch {
                    if let error = AppError.presentable(error) {
                    
                        appError = error
                        
                        failedRequest = request
                        
                        status = "PDF could not be saved."
                        
                        AppLogger.record(error, "Save webpage from Safari", request.url)
                        
                    } else {
                        status = "Save cancelled."
                    }
                }
                
                current = nil
                
                if appError != nil {
                    break
                }
            }
        }
    }

    func retry(_ modelContext: ModelContext) {
        
        guard let failedRequest, current == nil else {
            return
        }
        
        pending.insert(failedRequest, at: 0)
        
        self.failedRequest = nil
        
        appError = nil
        
        startProcessing(modelContext)
    }

    func dismissError(_ modelContext: ModelContext) {
        appError = nil
        
        
        failedRequest = nil
        
        startProcessing(modelContext)
    }

    func cancel() {
        
        pending.removeAll()
        
        task?.cancel()
        
        webPage?.stopLoading()
    }
}
