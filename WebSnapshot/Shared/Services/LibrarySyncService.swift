import Combine
import Foundation
import PDFKit
import SwiftData

@MainActor
final class LibrarySyncService: ObservableObject {
    @Published private(set) var state = LibrarySyncState()

    private var isRefreshing = false

    private var modeGeneration: UInt64 = 0

    private var indexCache = SyncIndexStore.Cache()

    static func settings(_ context: ModelContext) throws -> StorageSettings? {
        try LibrarySyncSettings.settings(context)
    }

    static func isEnabled(_ context: ModelContext) -> Bool {
        LibrarySyncSettings.isEnabled(context)
    }

    func requireReady() throws {
        if state.isSwitching {
            throw AppError.error("Wait for the library migration to finish before making changes.")
        }
    }

    static func localStorageURL(_ setting: StorageSettings) throws -> URL? {
        try LibrarySyncSettings.localStorageURL(setting)
    }

    func setEnabled(_ enabled: Bool, _ context: ModelContext, drive: URL? = nil, localRoot: URL? = nil) async throws {
        try requireReady()
        
        guard Self.isEnabled(context) != enabled else {
            return
        }
        
        modeGeneration &+= 1

        indexCache = SyncIndexStore.Cache()
        
        state.isSwitching = true
        
        state.lastError = nil
        
        defer {
            state.isSwitching = false
        }
        
        do {
            try context.save()
            
            if enabled {
                try await LibrarySyncMigration.enable(context, drive)
            }
            
            else {
                try await LibrarySyncMigration.disable(context,  localRoot)
            }
            
        } catch {
            context.rollback()
            
            state.lastError = AppError(error)
            
            throw error
        }
    }

    func reconnect(_ selected: URL, _ context: ModelContext) throws {
        do {
            try requireReady()
            try LibrarySyncSettings.reconnect(selected, context)
            indexCache = SyncIndexStore.Cache()
        } catch {
            context.rollback()
            throw error
        }
    }

    func refresh(_ context: ModelContext) async {
        
        guard Self.isEnabled(context), !state.isSwitching, !isRefreshing else {
            return
        }
        
        let generation = modeGeneration
        
        isRefreshing = true
        
        defer {
            isRefreshing = false
        }
        
        do {
            
            guard let setting = try Self.settings(context) else {
                return
            }
        
            let root = try folderURL(setting)
            
            let accessing = root.startAccessingSecurityScopedResource()
            
            defer {
                
                if accessing {
                    
                    root.stopAccessingSecurityScopedResource()
                
                }
            
            }
            
            let sentData = setting.pendingSyncChanges
            
            let pending = try LibrarySyncRepository.pendingChanges(setting)

            let pdfs = try LibrarySyncRepository.syncedPDFs(context)

            let deviceID = setting.syncDeviceID ?? UUID()

            let counter = setting.syncCounter

            let savedCache = indexCache
            
            let (index, cache) = try await Task.detached(priority: .utility) {
                
                let store = SyncIndexStore(root: root)

                var cache = savedCache
                
                try store.publish(pending)
                
                var index = try store.load(&cache)

                if !pending.files.isEmpty {
                    index = index.merging(pending)
                }

                let changes = try SyncMigration(root: root).reconcile(index, pdfs, deviceID, counter, &cache)

                try store.publish(changes)

                if !changes.files.isEmpty {
                    index = index.merging(changes)
                }
                
                try store.writeSnapshot(index, &cache)
            
                return (index, cache)
            }.value
            
            
            
            guard generation == modeGeneration, !state.isSwitching, Self.isEnabled(context), !Task.isCancelled else {
                return
            }

            indexCache = cache

            setting.syncDeviceID = deviceID
            
            
            
            try LibrarySyncRepository.applyRefresh(index, context, root, setting, sentData)

            if context.hasChanges {
                try context.save()
            }

            try LibraryService.retrySyncedFileDeletions(context, setting, root)
            
            state.lastError = nil
            
        } catch {
            
            guard generation == modeGeneration, !state.isSwitching, Self.isEnabled(context) else {
                return
            }
            
            context.rollback()
            
            let error = AppError(error)
            
            if state.lastError?.diagnosticMessage != error.diagnosticMessage {
                AppLogger.record(error, "Sync iCloud Drive library")
            }
            
            state.lastError = error
            
        }
        
    }

    func download(_ pdf: PDFFile, _ context: ModelContext) async throws {
        
        try Task.checkCancellation()

        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled else {
            return
        }
        
        let generation = modeGeneration
        
        let root = try folderURL(setting)
        
        let accessing = root.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
                
                root.stopAccessingSecurityScopedResource()
            
            }
        
        }
        
        let storedURL = pdf.url

        let url = try pdf.resolveURL()

        let previousHash = pdf.syncContentHash

        let id = pdf.libraryID

        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            try SyncFileStore.download(url)

            try Task.checkCancellation()

            let hash = try SyncFileStore.contentHash(url)

            try Task.checkCancellation()

            let currentURL: URL

            if let id, previousHash != hash {
                currentURL = try SyncFileStore(root: root).versionedURL(id, url, hash)
            } else {
                currentURL = url
            }

            return (currentURL, hash)
        }

        let (currentURL, hash) = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }

        try Task.checkCancellation()

        guard generation == modeGeneration, pdf.modelContext != nil, !pdf.isDeleted, pdf.url == storedURL, !state.isSwitching, Self.isEnabled(context), try pdf.resolveURL() == url else {
            
            throw AppError.error("The library changed during the download. Open the PDF again.")
            
        }
        
        try LibrarySyncRepository.updateLocation(pdf, currentURL, SyncFileStore(root: root).relativePath(currentURL), hash, setting)
        
        try context.save()
    }

    func folderURL(_ setting: StorageSettings) throws -> URL {
        try LibrarySyncSettings.folderURL(setting)
    }

    func reportError(_ error: Error) {
        state.lastError = AppError(error)
    }
}

@MainActor
enum LibrarySyncMigration {
    static func enable(_ context: ModelContext, _ selectedDrive: URL?) async throws {
        
        let setting = try LibrarySyncSettings.settings(context) ?? StorageSettings(.flexibility)
        
        if setting.modelContext == nil {
            context.insert(setting)
        }
        
        let drive = try selectedDrive.map(SyncFileStore.cloudDrive) ?? LibrarySyncSettings.driveURL(setting)
        let accessing = drive.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
                
                drive.stopAccessingSecurityScopedResource()
            
            }
        
        }
        
        let root = try SyncFileStore.prepareCloudFolder(drive)
        
        setting.syncDriveBookmarkData = try URL.securityScopedBookmarkData(drive)
        
        setting.syncDrivePath = drive.path
        
        let bookmark = try URL.securityScopedBookmarkData(root)
        
        let pdfs = try context.fetch(FetchDescriptor<PDFFile>())
        
        for pdf in pdfs where pdf.libraryID == nil {
            pdf.libraryID = UUID()
        }
        
        if setting.syncDeviceID == nil {
            setting.syncDeviceID = UUID()
        }
        
        
        try context.save()
        
        let local = try LibrarySyncRepository.localPDFs(pdfs)
        
        let deviceID = setting.syncDeviceID!
        
        let counter = setting.syncCounter
        
        let index = try await Task.detached(priority: .userInitiated) {
        
            try SyncMigration(root: root).prepareEnable(local, deviceID, counter)
        
        }.value
        
        try Task.checkCancellation()
        
        try LibrarySyncRepository.apply(index, context, root)
        
        setting.previousStorageRawValue = setting.storage.rawValue
        
        setting.previousFixedStoragePath = setting.fixedStoragePath
        
        setting.previousFixedStorageBookmarkData = setting.fixedStorageBookmarkData
        
        setting.syncFolderBookmarkData = bookmark
        
        setting.syncFolderPath = root.path
        
        setting.fixedStoragePath = root.path
        
        setting.fixedStorageBookmarkData = bookmark
        
        setting.storage = .fixed
        
        setting.syncCounter = max(setting.syncCounter, index.counter)
        
        setting.syncEnabled = true
        
        setting.pendingSyncChanges = nil
        
        try context.save()
    }

    static func disable(_ context: ModelContext, _ localRoot: URL?) async throws {
        
        guard let setting = try LibrarySyncSettings.settings(context) else {
            return
        }
        
        let root = try LibrarySyncSettings.folderURL(setting)
        
        let accessing = root.startAccessingSecurityScopedResource()
        
        defer {
        
            if accessing {
                root.stopAccessingSecurityScopedResource()
            }
            
        }
        
        let pending = try LibrarySyncRepository.pendingChanges(setting)

        try LibraryService.retrySyncedFileDeletions(context, setting, root)

        let pdfs = try LibrarySyncRepository.syncedPDFs(context)

        let deviceID = setting.syncDeviceID ?? UUID()

        let counter = setting.syncCounter
        
        guard let destination = try localRoot ?? LibrarySyncSettings.localStorageURL(setting) else {
            throw AppError.error("Choose a storage folder before turning Sync off.")
        }

        guard !FileIO.isInTrash(destination) else {
            throw AppError.error("Choose a storage folder outside the Trash before turning Sync off.")
        }
        
        let accessingDestination = destination.startAccessingSecurityScopedResource()
        
        defer {
            if accessingDestination {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        
        let storage = StorageSettings.Storage(rawValue: setting.previousStorageRawValue ?? "") ?? .flexibility
        
        let destinationBookmark = try storage == .fixed ? URL.securityScopedBookmarkData(destination) : nil
        
        let (index, urls) = try await Task.detached(priority: .userInitiated) {
            
            try SyncMigration(root: root).prepareDisable(pending, destination, pdfs, deviceID, counter)
            
        }.value
        
        try Task.checkCancellation()
        
        let knownIDs = Set(index.files.map(\.id))
        
        let cached = try context.fetch(FetchDescriptor<PDFFile>())
        
        guard cached.allSatisfy({
            $0.syncRelativePath == nil || $0.libraryID.map(knownIDs.contains) == true
        }) else {
            throw SyncStoreError.invalidIndex
        }
        
        try LibrarySyncRepository.apply(index, context,  root, urls)
        
        if storage == .fixed {
            try importFixedStorage(context, destination)
        }
        
        setting.storage = storage
        
        setting.fixedStoragePath = storage == .fixed ? destination.path : setting.previousFixedStoragePath
        
        setting.fixedStorageBookmarkData = destinationBookmark ?? setting.previousFixedStorageBookmarkData
        
        setting.previousStorageRawValue = nil
        
        setting.previousFixedStoragePath = nil
        
        setting.previousFixedStorageBookmarkData = nil
        
        setting.pendingSyncChanges = nil
        
        setting.syncEnabled = false
        
        setting.syncCounter = max(setting.syncCounter, index.counter)
        
        try context.save()
    }

    private static func importFixedStorage(_ context: ModelContext, _ directory: URL) throws {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
        
        for url in urls where url.pathExtension.lowercased() == "pdf" {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            
            guard values.isRegularFile == true, values.isSymbolicLink != true else {
                continue
            }
            
            guard try PDFFileService.entries(context, matching: url).isEmpty else {
                continue
            }
            
            guard let document = PDFDocument(url: url), document.pageCount > 0 || document.isLocked else {
                continue
            }
            
            try PDFFileService.register(context, url)
        }
    }
}

nonisolated struct SyncMigration: Sendable {
    var root: URL

    func reconcile(_ index: SyncIndex, _ pdfs: [SyncLocalPDF], _ deviceID: UUID, _ counter: Int64, _ cache: inout SyncIndexStore.Cache) throws -> SyncIndex {
        let known = Dictionary(pdfs.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let store = SyncFileStore(root: root)

        var next = max(index.counter, counter)

        var changes = SyncIndex()

        for record in index.files where !record.isDeleted {
            guard let location = record.location else {
                continue
            }

            let pdf = known[record.id]

            let preferred = pdf?.relativePath == location.relativePath && pdf?.sharedHash == location.contentHash ? pdf?.url : nil

            guard var current = try store.currentLocation(location, preferredURL: preferred, cache: &cache),
                  current.relativePath != location.relativePath || current.contentHash != location.contentHash else {
                continue
            }

            guard next < Int64.max - 1 else {
                throw SyncStoreError.invalidIndex
            }

            next += 1

            if current.contentHash != location.contentHash {
                let source = try store.fileURL(current.relativePath)
                let destination = try store.versionedURL(record.id, source, current.contentHash)

                current.relativePath = try store.relativePath(destination)
            }

            current.stamp = SyncStamp(counter: next, deviceID: deviceID, operationID: UUID())

            changes.files.append(SyncPDFRecord(id: record.id, location: current, tags: nil, deleted: nil))
        }

        return changes
    }

    func prepareEnable(_ pdfs: [SyncLocalPDF], _ deviceID: UUID,  _ counter: Int64) throws -> SyncIndex {
        
        try FileManager.default.createDirectory( at: root, withIntermediateDirectories: true)
        
        var index = try SyncIndexStore(root: root).load()

        var cache = SyncIndexStore.Cache()

        var changes = try reconcile(index, [], deviceID, counter, &cache)

        index = index.merging(changes)
        
        var next = max(counter, index.counter)
        
        for pdf in pdfs {
            
            let existing = index.files.first {
            
                $0.id == pdf.id
            
            }
            
            if existing?.isDeleted == true {
                
                continue
            
            }
            
            let hash = try SyncFileStore.contentHash(pdf.url)
            
            guard next < Int64.max - 1 else {
                
                throw SyncStoreError.invalidIndex
            
            }
            
            next += 1
            
            let stamp = SyncStamp( counter: next, deviceID: deviceID, operationID: UUID() )
            
            
            var location: SyncPDFLocation
            
            if let current = existing?.location, current.contentHash == hash || pdf.sharedHash == hash {
            
                location = current
                
                if current.contentHash == hash {
                    try SyncFileStore.copy(pdf.url, to: SyncFileStore(root: root).fileURL(current.relativePath), expectedHash: hash)
                }
                
            } else {
                
                let path = SyncFileStore.relativePath(pdf.id, hash, pdf.url.lastPathComponent)
                
                let destination = try SyncFileStore(root: root).fileURL(path)
                
                try SyncFileStore.copy(pdf.url, to: destination, expectedHash: hash)
                
                location = SyncPDFLocation( relativePath: path, contentHash: hash, addedAt: pdf.addedAt, stamp: stamp)
                
            }
            
            
            var tags: SyncPDFTags
            
            if let current = existing?.tags, let baseline = pdf.baselineTags {
                
                tags = pdf.tagNames == baseline ? current : SyncPDFTags( editing: pdf.tagNames, previous: baseline, stamp)
                
            } else {
                
                tags = SyncPDFTags( pdf.tagNames,  stamp)
                
            }
            
            
            tags.stamp = stamp
            
            let record = SyncPDFRecord( id: pdf.id, location: location, tags: tags, deleted: nil)
            
            changes = changes.merging(SyncIndex(files: [record]))
            
            index = index.merging( SyncIndex( files: [record] ) )
            
        }
        
        
        try SyncIndexStore(root: root).publish(changes)
        
        try SyncIndexStore(root: root).writeSnapshot(index)
        
        return index
    }

    func prepareDisable(_ pending: SyncIndex, _ localRoot: URL, _ pdfs: [SyncLocalPDF] = [], _ deviceID: UUID = UUID(), _ counter: Int64 = 0) throws -> (SyncIndex, [UUID: URL]) {
        
        try SyncIndexStore(root: root).publish(pending)
        
        var index = try SyncIndexStore(root: root).load().merging(pending)

        var cache = SyncIndexStore.Cache()

        let changes = try reconcile(index, pdfs, deviceID, counter, &cache)

        try SyncIndexStore(root: root).publish(changes)

        index = index.merging(changes)

        if !changes.files.isEmpty {
            try SyncIndexStore(root: root).writeSnapshot(index)
        }
        
        var destinations: [UUID: URL] = [:]

        var usedDestinations: Set<URL> = []
        
        for (offset, record) in index.files.enumerated() where !record.isDeleted {
        
            guard var location = record.location else {
                throw SyncStoreError.invalidIndex
            }
            
            let source = try SyncFileStore(root: root).fileURL(location.relativePath)
            
            location.contentHash = try SyncFileStore.contentHash(source)
            
            index.files[offset].location = location
            
            var destination = localRoot.appendingPathComponent(source.lastPathComponent)
            
            var suffix = 2
            
            while try SyncFileStore.isPresent(destination) {
                let canonical = destination.resolvingSymlinksInPath().standardizedFileURL

                let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])

                if !usedDestinations.contains(canonical), values.isRegularFile == true, values.isSymbolicLink != true,
                   try SyncFileStore.contentHash(destination) == location.contentHash {
                    break
                }

                destination = localRoot.appendingPathComponent(URL.pdfFileName(source.lastPathComponent, nil, " \(suffix)"))
                suffix += 1
            }
            
            try SyncFileStore.copy(source, to: destination, expectedHash: location.contentHash)
            
            destinations[record.id] = destination

            usedDestinations.insert(destination.resolvingSymlinksInPath().standardizedFileURL)
            
        }
        
        return (index, destinations)
        
    }
}
