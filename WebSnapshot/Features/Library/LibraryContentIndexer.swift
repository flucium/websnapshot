import Foundation
import Combine
import SwiftData

@MainActor
final class LibraryContentIndexer: ObservableObject {
    
    @Published private(set) var pendingCount = 0
    
    @Published private var failedSources: [PersistentIdentifier: String] = [:]

    private var isRunning = false

    private let extract: @Sendable (URL) async throws -> String

    
    var failedCount: Int {
        failedSources.count
    }

    
    init(extract: @escaping @Sendable (URL) async throws -> String = {
        try await PDFContentService().text($0)
    }) {
        self.extract = extract
    }

    func retry() {
        failedSources.removeAll()
    }

    func index(_ pdfFiles: [PDFFile], _ modelContext: ModelContext) async {
        
        guard isRunning == false else {
            return
        }
        
        isRunning = true
        
        defer {
            if pendingCount != 0 {
                pendingCount = 0
            }
            
            isRunning = false
        }

        let liveIDs = Set(pdfFiles.map(\.persistentModelID))
        
        let retainedFailures = failedSources.filter {
            liveIDs.contains($0.key)
        }
        
        if retainedFailures != failedSources {
            failedSources = retainedFailures
        }
        
        var requests: [(id: PersistentIdentifier, url: URL, fingerprint: String, source: String)] = []
        
        var invalidated = false

        for pdfFile in pdfFiles {
            
            if Task.isCancelled {
                return
            }
            
            do {
                let url = try pdfFile.resolveURL()
                
                guard FileIO.availability(url) == .available else {
                    continue
                }
                
                let fingerprint = try PDFContentService.fingerprint(url)
                
                if pdfFile.searchableText != nil, pdfFile.contentFingerprint == fingerprint {
                    failedSources[pdfFile.persistentModelID] = nil
                    
                    continue
                }

                if pdfFile.searchableText != nil || pdfFile.contentFingerprint != nil {
                    pdfFile.searchableText = nil
                    
                    pdfFile.contentFingerprint = nil
                    
                    invalidated = true
                }
                
                let source = "\(url.standardizedFileURL.path):\(fingerprint)"
                
                guard failedSources[pdfFile.persistentModelID] != source else {
                    continue
                }
                
                requests.append((pdfFile.persistentModelID, url, fingerprint, source))
                
            } catch {
                
                let source = pdfFile.url.absoluteString
                
                if failedSources[pdfFile.persistentModelID] != source {
                    
                    AppLogger.record(AppError(error), "Prepare PDF content search", pdfFile.url)
                    
                    failedSources[pdfFile.persistentModelID] = source
                }
            }
        }

        if invalidated {
            do {
                try modelContext.save()
            } catch {
                AppLogger.record(AppError(error), "Clear outdated PDF content search")
                return
            }
        }

        guard requests.isEmpty == false else {
            return
        }
        
        pendingCount = requests.count
        
        for request in requests {
            defer {
                pendingCount -= 1
            }
            
            do {
                try Task.checkCancellation()
                
                let text = try await extract(request.url)
                
                try Task.checkCancellation()

                guard let pdfFile = try modelContext.fetch(FetchDescriptor<PDFFile>()).first(where: {
                    $0.persistentModelID == request.id
                }), try PDFContentService.fingerprint(pdfFile.resolveURL()) == request.fingerprint else {
                    continue
                }

                pdfFile.searchableText = text
                
                pdfFile.contentFingerprint = request.fingerprint
                
                do {
                    try modelContext.save()
                } catch {
                
                    pdfFile.searchableText = nil
                    
                    pdfFile.contentFingerprint = nil
                    
                    throw error
                }
                
                failedSources[request.id] = nil
                
            } catch is CancellationError {
                return
            } catch {
                
                if Task.isCancelled {
                    return
                }
                
                failedSources[request.id] = request.source
                
                AppLogger.record(AppError(error), "Prepare PDF content search", request.url)
            }
        }
    }
}
