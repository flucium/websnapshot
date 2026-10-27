import Combine
import Foundation
import SwiftData

@MainActor
final class LibraryContentService: ObservableObject {

    @Published private(set) var state = LibraryContentState()

    private let sync: LibrarySyncService

    private var indexTask: Task<Void, Never>?

    private(set) var cacheRefreshTask: Task<Void, Error>?

    private let extract: @Sendable (URL) async throws -> String

    private var failedSources: [PersistentIdentifier: String] = [:] {
        didSet {
            if state.failedCount != failedSources.count {
                state.failedCount = failedSources.count
            }
        }
    }

    
    init(sync: LibrarySyncService, _ extract: @escaping @Sendable (URL) async throws -> String = {
        try await PDFContentService().text($0)
    }) {
        self.sync = sync
        self.extract = extract
    }

    func retry() {
        failedSources.removeAll()
    }

    func index(_ pdfFiles: [PDFFile], _ modelContext: ModelContext) async {
        guard !Task.isCancelled, !state.isRefreshingCache, !sync.state.isSwitching else {
            return
        }

        if let indexTask {
            await indexTask.value
            return
        }

        let task = Task(priority: .utility) { @MainActor in
            defer {
                self.indexTask = nil
            }

            await self.indexContent(pdfFiles, modelContext)
        }

        indexTask = task

        await task.value
    }

    @discardableResult
    func refreshContentCache(_ modelContext: ModelContext) -> Task<Void, Error>? {
        guard !state.isRefreshingCache, !sync.state.isSwitching else {
            return nil
        }

        state.isRefreshingCache = true

        state.cacheRefreshResult = nil

        let task = Task(priority: .utility) { @MainActor in
            defer {
                self.state.isRefreshingCache = false
                self.cacheRefreshTask = nil
            }

            try Task.checkCancellation()

            if let indexTask = self.indexTask {
                indexTask.cancel()
                await indexTask.value
            }

            try Task.checkCancellation()

            try sync.requireReady()

            let removedCount = try self.invalidateContentCache(modelContext)

            let pdfFiles = try modelContext.fetch(FetchDescriptor<PDFFile>())

            self.retry()

            await self.indexContent(pdfFiles, modelContext)

            try Task.checkCancellation()

            try sync.requireReady()

            let afterIndexing = try modelContext.fetch(FetchDescriptor<PDFFile>())

            try LibraryService.deleteMissingFiles(modelContext, afterIndexing, sync: sync)

            let remaining = try modelContext.fetch(FetchDescriptor<PDFFile>())

            let refreshedCount = remaining.filter {
                $0.searchableText != nil
            }.count

            self.state.cacheRefreshResult = LibraryContentState.CacheRefreshResult(refreshedCount: refreshedCount, removedCount: removedCount + afterIndexing.count - remaining.count, unavailableCount: remaining.count - refreshedCount)
        }

        cacheRefreshTask = task

        return task
    }

    private func invalidateContentCache(_ modelContext: ModelContext) throws -> Int {
        do {
            let pdfFiles = try modelContext.fetch(FetchDescriptor<PDFFile>())

            try LibraryService.deleteMissingFiles(modelContext, pdfFiles, sync: sync)

            let remaining = try modelContext.fetch(FetchDescriptor<PDFFile>())

            for pdfFile in remaining {
                pdfFile.searchableText = nil
                pdfFile.contentFingerprint = nil
            }

            if modelContext.hasChanges {
                try modelContext.save()
            }

            return pdfFiles.count - remaining.count
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    private func indexContent(_ pdfFiles: [PDFFile], _ modelContext: ModelContext) async {

        guard state.isIndexing == false, !sync.state.isSwitching else {
            return
        }

        state.isIndexing = true

        defer {

            if state.pendingCount != 0 {
                state.pendingCount = 0
            }

            state.isIndexing = false
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

            if Task.isCancelled || sync.state.isSwitching {
                return
            }

            if pdfFile.syncRelativePath != nil, pdfFile.availability != .available {
                continue
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

                requests.append( ( pdfFile.persistentModelID, url, fingerprint, source) )

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

        state.pendingCount = requests.count

        for request in requests {

            defer {
                state.pendingCount -= 1
            }

            do {

                try Task.checkCancellation()

                let text = try await extract(request.url)

                if sync.state.isSwitching {
                    return
                }

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
