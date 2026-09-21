import Foundation
import SwiftData
import WebKit

@MainActor
final class FetchViewService {
    
    static func loadWebPage(_ state: FetchViewState) {
    
        let input = state.searchText
        
        let requestID = state.beginLoad()
        
        state.appError = nil
        
        state.failedOperation = nil

        state.loadTask = Task {
            do {
                _ = try await fetch(input) { page in
                    guard state.isCurrentLoad(requestID) else {
                        return
                    }
                    
                    state.webPage = page
                }
        
                try Task.checkCancellation()
                
                guard state.isCurrentLoad(requestID) else {
                    return
                }
                
                state.appError = nil
                
                state.failedOperation = nil
                
                state.finishLoad(requestID)
            } catch {
                
                guard state.isCurrentLoad(requestID) else {
                    return
                }
                
                handle(error,  .load,  state,  URL.supportedWebURL(input))
                
                state.finishLoad(requestID)
            }
        }
    }

    static func saveWebPage(_ state: FetchViewState,_ modelContext: ModelContext,_ storageSettings: [StorageSettings]) {
        let page = state.webPage
        
        let title = page.title
        
        let url = page.url

        Task {
            do {
                let document = try await WebService.export(page)
        
                state.pdfFileDocument = document

                guard try WebCaptureService.save(
                    document,
                     title,
                     url,
                     modelContext,
                     storageSettings
                ) != nil else {
                    return
                }

                state.appError = nil
                
                state.failedOperation = nil
            } catch {
                handle(error, .save,  state, url)
            }
        }
    }

    static func retryFailedOperation( _ state: FetchViewState, _ modelContext: ModelContext, _ storageSettings: [StorageSettings] ) {
        switch state.failedOperation {
            
        case .load:
            loadWebPage(state)
        case .save:
            saveWebPage(state, modelContext, storageSettings)
        case nil:
            break
        }
        
    }

    static func fetch(_ input: String, _ onStart: (WebPage) -> Void = { _ in }) async throws -> WebPage {
        
        guard let url = URL.supportedWebURL(input) else {
            throw AppError.invalidURL("Enter a valid HTTP or HTTPS address.")
        }

        do {
            return try await WebService.fetch(url, onStart)
            
        } catch let error as CancellationError {
            throw error
            
        } catch let error as AppError {
            throw error
            
        } catch {
        
            throw AppError.invalidLoad(
                "The webpage could not be loaded.",
                error.localizedDescription,
                error
            )
        }
        
    }

    private static func handle(_ error: Error,_ operation: FetchViewState.Operation,_ state: FetchViewState,_ targetURL: URL? = nil) {
        guard let appError = AppError.presentable(error) else {
            return
        }

        AppLogger.record(
            appError,
            operation == .load ? "Load webpage" : "Save webpage as PDF",
            targetURL ?? (operation == .load
                ? URL.supportedWebURL(state.searchText)
                : state.webPage.url)
        )
        
        state.failedOperation = operation
        
        state.appError = appError
    }
}
