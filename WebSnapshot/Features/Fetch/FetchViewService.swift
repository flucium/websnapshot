import Foundation
import SwiftData
import WebKit

@MainActor
final class FetchViewService {
    
    static func loadWebPage(_ fetchViewState: FetchViewState) {
    
        let input = fetchViewState.searchText
        
        let requestID = fetchViewState.beginLoad()
        
        fetchViewState.appError = nil
        
        fetchViewState.failedOperation = nil

        fetchViewState.loadTask = Task {
            do {
                _ = try await fetch(input) {
                    page in
                    
                    guard fetchViewState.isCurrentLoad(requestID) else {
                        return
                    }
                    
                    fetchViewState.webPage = page
                }
        
                try Task.checkCancellation()
                
                guard fetchViewState.isCurrentLoad(requestID) else {
                    return
                }
                
                fetchViewState.appError = nil
                
                fetchViewState.failedOperation = nil
                
                fetchViewState.finishLoad(requestID)
            } catch {
                
                guard fetchViewState.isCurrentLoad(requestID) else {
                    return
                }
                
                handle(error,  .load,  fetchViewState,  URL.supportedWebURL(input))
                
                fetchViewState.finishLoad(requestID)
            }
        }
    }

    static func saveWebPage(_ fetchViewState: FetchViewState,_ modelContext: ModelContext,_ storageSettings: [StorageSettings], _ librarySyncService: LibrarySyncService) {
        
        guard let requestID = fetchViewState.beginSave() else {
            return
        }
        
        let page = fetchViewState.webPage
        
        let url = page.url

        fetchViewState.saveTask = Task {
            defer {
                fetchViewState.finishSave(requestID)
            }
            
            do {
                let document = try await WebPDFService.export(page) {
                    progress in

                    guard !Task.isCancelled, fetchViewState.webPage === page else {
                        return
                    }

                    fetchViewState.updateExportState(progress, requestID)
                }

                try Task.checkCancellation()
                
                guard fetchViewState.isCurrentSave(requestID), fetchViewState.webPage === page else {
                    return
                }
                
                guard try LibraryService.savePDF(document.data, URL.pdfFileName(page.title, page.url), modelContext, storageSettings, librarySyncService, chooseDestination: { name in
                    
                    let destination = savePanel(name)

                    return Task.isCancelled ? nil : destination
                }) != nil else {
                    return
                }

                fetchViewState.appError = nil
                
                fetchViewState.failedOperation = nil
                
            } catch {
                guard fetchViewState.isCurrentSave(requestID) else {
                    return
                }
                
                handle(error, .save,  fetchViewState, url)
            }
        }
    }

    static func retryFailedOperation( _ fetchViewState: FetchViewState, _ modelContext: ModelContext, _ storageSettings: [StorageSettings], _ librarySyncService: LibrarySyncService ) {
        switch fetchViewState.failedOperation {
            
        case .load:
            loadWebPage(fetchViewState)
            
        case .save:
            saveWebPage(fetchViewState, modelContext, storageSettings,  librarySyncService)
            
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
        
            throw AppError.invalidLoad("The webpage could not be loaded.", error.localizedDescription, error)
        }
        
    }

    private static func handle(_ error: Error,_ operation: FetchViewState.Operation,_ fetchViewState: FetchViewState,_ targetURL: URL? = nil) {
        guard let appError = AppError.presentable(error) else {
            return
        }

        AppLogger.record(appError, operation == .load ? "Load webpage" : "Save webpage as PDF", targetURL ?? (operation == .load ? URL.supportedWebURL(fetchViewState.searchText) : fetchViewState.webPage.url) )
        
        fetchViewState.failedOperation = operation
        
        fetchViewState.appError = appError
    }
}
