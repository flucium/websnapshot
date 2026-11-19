import Foundation
import PDFKit
import SwiftData

@MainActor
enum LibraryService {
    static func savePDF(_ data: Data, _ fileName: String, _ context: ModelContext, _ storageSettings: [StorageSettings], _ librarySyncService:LibrarySyncService, chooseDestination: ((String) -> URL?)? = nil) throws -> URL? {
        
        try librarySyncService.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            return try saveSyncedPDF(data, fileName, context)
        }

        switch StorageSettingsService.storage(storageSettings) {
        case .flexibility:
            guard let destination = chooseDestination?(fileName) else {
                return nil
            }
            
            try refreshLocations(context,  librarySyncService)
            
            try PDFFileStore.write(data, to: destination) {
                try registerPDF(context, $0, librarySyncService)
            }
            
            return destination
            
        case .fixed:
            guard let directory = try StorageSettingsService.fixedStorageURL(storageSettings, librarySyncService) else {
                throw AppError.error("Choose a storage folder in Settings before saving.")
            }
            
            let accessing = directory.startAccessingSecurityScopedResource()
            
            defer {
                if accessing {
                    directory.stopAccessingSecurityScopedResource()
                }
            }
            
            try refreshLocations(context, librarySyncService)
            
            return try PDFFileStore.save(data, fileName, in: directory) {
                try registerPDF(context, $0, librarySyncService)
            }
        }
    }

    static func registerPDF(_ context: ModelContext, _ url: URL, _ librarySyncService: LibrarySyncService) throws {
        try librarySyncService.requireReady()
        
        
        try update(context, "The PDF could not be added to the library.") {
            
            if LibrarySyncService.isEnabled(context) {
                try registerSyncedPDF(url, context)
            } else {
                try PDFFileService.register(context, url)
            }
            
            return true
        }
        
    }

    static func importPDF(_ source: URL, _ directory: URL, _ context: ModelContext, _ librarySyncService: LibrarySyncService ) throws -> URL {
        
        try librarySyncService.requireReady()
        
        let accessingSource = source.startAccessingSecurityScopedResource()
        
        let accessingDirectory = directory.startAccessingSecurityScopedResource()
        
        defer {
            if accessingSource {
                source.stopAccessingSecurityScopedResource()
            }
            
            if accessingDirectory {
                directory.stopAccessingSecurityScopedResource()
            }
            
        }
        
        guard source.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: source), document.pageCount > 0 || document.isLocked else {
            throw AppError.invalidFileType("Choose a valid PDF file to import.")
        }
        
        if LibrarySyncService.isEnabled(context) {
            let data = try SyncFileStore.coordinatedRead(source) {
                try Data(contentsOf: $0)
            }
            
            
            return try saveSyncedPDF(data, source.lastPathComponent, context)
        }
        
        if source.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL
        {
            try registerPDF(context, source, librarySyncService)
            
            return source
        }
        
        do {
            
            return try PDFFileStore.copy(source, to: directory) {
                try registerPDF(context, $0, librarySyncService)
            }
            
        } catch {
            throw AppError(error)
        }
    }

    static func exportPDF(_ source: URL, _ destination: URL) throws {
        do {
            try PDFFileStore.export(source, to: destination)
        } catch {
            throw AppError(error)
        }
    }

    static func delete(_ context: ModelContext, _ url: URL, _ resolvedURL: URL, _ librarySyncService: LibrarySyncService, _ removeFile: ((URL) throws -> Void)? = nil ) throws {
        
        try librarySyncService.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            try removePDFRecords(context, url, librarySyncService, removeFile)
            return
        }
        
        let settings = try LibrarySyncSettings.settings(context)

        try (removeFile ?? ((settings?.moveDeletedFilesToTrash ?? true) ? FileIO.moveToTrash : FileIO.delete))(resolvedURL)
        
        do {
            try removePDFRecords(context, url, librarySyncService)
        } catch {
            AppLogger.recordDiagnostic("The file was deleted, but its library entry could not be removed. Automatic synchronization will retry the cleanup.", "Delete PDF library entry", resolvedURL)
            
            throw error
            
        }
    }

    static func deleteAll(_ context: ModelContext, _ librarySyncService: LibrarySyncService, _ removeFile: ((URL) throws -> Void)? = nil) throws {
        try librarySyncService.requireReady()

        let pdfFiles = try context.fetch(FetchDescriptor<PDFFile>())

        if LibrarySyncService.isEnabled(context) {
            try removeSyncedPDFRecords(context, pdfFiles, librarySyncService, removeFile)
        } else {
            for pdfFile in pdfFiles where pdfFile.modelContext != nil && !pdfFile.isDeleted {
                if pdfFile.availability == .missing {
                    try removePDFRecords(context, pdfFile.url, librarySyncService)
                } else {
                    try delete(context, pdfFile.url, pdfFile.resolveURL(), librarySyncService, removeFile)
                }
            }
        }

        try update(context, "The library's tags could not be deleted.") {
            let tags = try context.fetch(FetchDescriptor<PDFTag>())
            
            for tag in tags {
                context.delete(tag)
            }
            return !tags.isEmpty
        }
    }

    static func removePDFRecords(_ context: ModelContext, _ url: URL, _ librarySyncService: LibrarySyncService, _ removeFile: ((URL) throws -> Void)? = nil) throws {
        try librarySyncService.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            try removeSyncedPDFRecords(context, url, librarySyncService, removeFile)
            return
        }
        
        try update(context, "The PDF could not be removed from the library.") {
            
            let matched = try PDFFileService.entries(context, matching: url)
        
            PDFFileService.remove(matched, context)
            
            return !matched.isEmpty
        }
    }

    static func replaceTags(_ names: [String], _ pdfFile: PDFFile, _ context: ModelContext,_ librarySyncService: LibrarySyncService) throws {
        
        try librarySyncService.requireReady()
        
        guard pdfFile.modelContext != nil, !pdfFile.isDeleted else {
            throw AppError.error("This PDF is no longer in the library.")
        }
        
        let previous = PDFTagService.tagNames(pdfFile.tags)
        
        try update(context, "The tags could not be saved.") {
        
            try PDFTagService.replaceTags(names, pdfFile, context)
            
            if let setting = try LibrarySyncSettings.settings(context), setting.syncEnabled {
                try LibrarySyncRepository.queueTags(PDFTagService.tagNames(pdfFile.tags), previous: previous, pdfFile, setting)
            }
            
            return true
        }
    }

    static func refreshLocations(_ context: ModelContext, _ librarySyncService: LibrarySyncService) throws {
        try librarySyncService.requireReady()
        
        guard !LibrarySyncService.isEnabled(context) else {
            return
        }
        
        try update(context, "The library's file locations could not be updated before saving.") {
            try PDFFileService.refreshLocations(context)
        }
    }

    static func deleteMissingFiles(_ context: ModelContext, _ pdfFiles: [PDFFile], _ librarySyncService: LibrarySyncService,_ confirmedDeletedIDs: Set<PersistentIdentifier> = []) throws {
        
        guard !librarySyncService.librarySyncState.isSwitching, !LibrarySyncService.isEnabled(context) else {
            return
        }
        
        try update(context, "The library could not be synchronized.") {
            PDFFileService.deleteMissingFiles(context, pdfFiles, confirmedDeletedIDs)
        }
    }

    private static func saveSyncedPDF(_ data: Data, _ fileName: String, _ context: ModelContext) throws -> URL {
        guard let setting = try LibrarySyncSettings.settings(context), setting.syncEnabled else {
            throw AppError.error("Sync is not enabled.")
        }

        let root = try LibrarySyncSettings.folderURL(setting)
        let id = UUID()

        return try SyncFileStore(root: root).write(data, fileName, id) { url, hash in
            try update(context, "The PDF could not be added to the library.") {
                try registerSyncedPDF(url, context, id: id, hash: hash)
                return true
            }
        }
    }

    private static func registerSyncedPDF(_ url: URL, _ context: ModelContext, id: UUID? = nil, hash: String? = nil) throws {
        guard let setting = try LibrarySyncSettings.settings(context), setting.syncEnabled else {
            return
        }

        let root = try LibrarySyncSettings.folderURL(setting)
        let accessing = root.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let path = try SyncFileStore(root: root).relativePath(url)
        let contentHash = try hash ?? SyncFileStore.contentHash(url)

        try LibrarySyncRepository.registerPDF(url, context, setting, path, contentHash, id: id)
    }

    private static func removeSyncedPDFRecords(_ context: ModelContext, _ url: URL, _ librarySyncService: LibrarySyncService, _ removeFile: ((URL) throws -> Void)?) throws {
        let pdfs = try PDFFileService.entries(context, matching: url).filter {
            $0.libraryID != nil
        }
        try removeSyncedPDFRecords(context, pdfs, librarySyncService, removeFile)
    }

    private static func removeSyncedPDFRecords(_ context: ModelContext, _ pdfFiles: [PDFFile], _ librarySyncService: LibrarySyncService, _ removeFile: ((URL) throws -> Void)?) throws {
        
        guard let setting = try LibrarySyncSettings.settings(context), setting.syncEnabled else {
            return
        }

        let root = try LibrarySyncSettings.folderURL(setting)
        let files = SyncFileStore(root: root)
        var paths = Set(try setting.pendingSyncDeletions.map {
            try JSONDecoder().decode([String].self, from: $0)
        } ?? [])

        try update(context, "The PDF could not be removed from the library.") {
            for pdfFile in pdfFiles {
                let path = try files.relativePath((try? pdfFile.resolveURL()) ?? pdfFile.url)

                paths.insert(path)

                if let id = pdfFile.libraryID {
                    paths.insert(SyncFileStore.versionDirectory(id))
                }
            }

            try LibrarySyncRepository.remove(pdfFiles, context, setting)

            setting.pendingSyncDeletions = paths.isEmpty ? nil : try JSONEncoder().encode(paths.sorted())

            return !pdfFiles.isEmpty
        }

        do {
            try retrySyncedFileDeletions(context, setting, root, removeFile)
        } catch {
            librarySyncService.reportError(error)
            throw error
        }
    }

    static func retrySyncedFileDeletions(_ context: ModelContext, _ storageSettings: StorageSettings, _ root: URL, _ removeFile: ((URL) throws -> Void)? = nil) throws {
        guard let data = storageSettings.pendingSyncDeletions else {
            return
        }

        let paths = try JSONDecoder().decode([String].self, from: data)

        let accessing = root.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                root.stopAccessingSecurityScopedResource()
            }
        }

        var remaining: [String] = []

        var firstError: Error?

        let files = SyncFileStore(root: root)

        SyncFileStore.withVersionLock {
            var removed: Set<URL> = []

            for path in paths {
                do {
                    for url in try files.deletionURLs(path) where !removed.contains(url) {
                        if let removeFile {
                            try removeFile(url)
                        } else if try SyncFileStore.isPresent(url) {
                            if storageSettings.moveDeletedFilesToTrash {
                                try SyncFileStore.coordinatedWrite(url) {
                                    if FileIO.exists($0) {
                                        try FileIO.moveToTrash($0)
                                    }
                                }
                            } else {
                                try SyncFileStore.remove(url)
                            }
                        }

                        removed.insert(url)
                    }
                } catch {
                    remaining.append(path)
                    firstError = firstError ?? error
                }
            }
        }

        if remaining != paths {
            storageSettings.pendingSyncDeletions = remaining.isEmpty ? nil : try JSONEncoder().encode(remaining)
            try context.save()
        }

        if let firstError {
            throw firstError
        }
    }

    private static func update(_ context: ModelContext, _ message: String,_ operation: () throws -> Bool) throws {
        
        do {
            
            if try operation(), context.hasChanges {
                try context.save()
            }
            
        } catch {
            context.rollback()
            
            if let error = error as? AppError {
                throw error
            }
            
            throw AppError.system(message, error.localizedDescription, error)
        }
    }
}

@MainActor
enum LibrarySyncRepository {
    static func syncedPDFs(_ context: ModelContext) throws -> [SyncLocalPDF] {
        try context.fetch(FetchDescriptor<PDFFile>()).compactMap {
            pdfFile in
            guard let id = pdfFile.libraryID, let path = pdfFile.syncRelativePath else {
                return nil
            }

            return SyncLocalPDF(id: id, url: (try? pdfFile.resolveURL()) ?? pdfFile.url, addedAt: pdfFile.addedAt,
                                tagNames: [], sharedHash: pdfFile.syncContentHash, relativePath: path)
        }
    }

    static func updateLocation(_ pdfFile: PDFFile, _ url: URL, _ path: String, _ hash: String, _ storageSettings: StorageSettings) throws {
        guard let id = pdfFile.libraryID else {
            throw SyncStoreError.invalidIndex
        }

        if pdfFile.syncRelativePath != path || pdfFile.syncContentHash != hash {
            let location = SyncPDFLocation(relativePath: path, contentHash: hash, addedAt: pdfFile.addedAt,
                                           stamp: try nextStamp(storageSettings))

            try enqueue(SyncPDFRecord(id: id, location: location, tags: nil, deleted: nil), storageSettings)

            if pdfFile.syncContentHash != hash {
                pdfFile.searchableText = nil
                pdfFile.contentFingerprint = nil
            }

            pdfFile.url = url
            pdfFile.syncRelativePath = path
            pdfFile.syncContentHash = hash
            pdfFile.syncBaselineContentHash = hash
        }

        pdfFile.bookmarkData = try URL.securityScopedBookmarkData(url)
    }

    static func localPDFs(_ pdfFiles: [PDFFile]) throws -> [SyncLocalPDF] {
        try pdfFiles.map {
            pdfFile in
            
            SyncLocalPDF(id: pdfFile.libraryID!, url: try pdfFile.resolveURL(), addedAt: pdfFile.addedAt, tagNames: PDFTagService.tagNames(pdfFile.tags), sharedHash: pdfFile.syncBaselineContentHash, baselineTags: try pdfFile.syncBaselineTags.map {
                try JSONDecoder().decode([String].self, from: $0)
            })
            
        }
    }

    static func registerPDF(_ url: URL, _ context: ModelContext, _ storageSettings: StorageSettings, _ path: String, _ hash: String, id: UUID? = nil) throws {
        let entries = try context.fetch( FetchDescriptor<PDFFile>() )
        
        
        let pdfFile = entries.first {
            $0.url.standardizedFileURL == url.standardizedFileURL
        } ?? PDFFile( url, nil, Date() )
        
        if pdfFile.modelContext == nil {
            
            context.insert(pdfFile)
        
        }
        
        
        pdfFile.libraryID = pdfFile.libraryID ?? id ?? UUID()
        
        pdfFile.url = url
        
        pdfFile.bookmarkData = try URL.securityScopedBookmarkData(url)
        
        pdfFile.syncRelativePath = path
        
        pdfFile.syncContentHash = hash
        
        pdfFile.syncBaselineContentHash = pdfFile.syncContentHash
        
        pdfFile.syncBaselineTags = try JSONEncoder().encode(PDFTagService.tagNames(pdfFile.tags))
        
        pdfFile.searchableText = nil
        
        pdfFile.contentFingerprint = nil
        
        let stamp = try nextStamp(storageSettings)
        
        let record = SyncPDFRecord( id: pdfFile.libraryID!, location: SyncPDFLocation(relativePath: path, contentHash: pdfFile.syncContentHash!, addedAt: pdfFile.addedAt, stamp: stamp ), tags: SyncPDFTags(PDFTagService.tagNames(pdfFile.tags), stamp), deleted: nil)
        
        try enqueue(record, storageSettings)
        
    }

    static func queueTags(_ names: [String], previous: [String], _ pdfFile: PDFFile, _ storageSettings: StorageSettings) throws {
        guard let id = pdfFile.libraryID else {
            return
        }

        try enqueue( SyncPDFRecord( id: id, location: nil, tags: SyncPDFTags(editing: names, previous: previous, try nextStamp(storageSettings) ), deleted: nil ), storageSettings)
        
        pdfFile.syncBaselineTags = try JSONEncoder().encode(names)
        
    }

    static func remove(_ pdfFiles: [PDFFile], _ context: ModelContext, _ storageSettings: StorageSettings) throws {
        for pdfFile in pdfFiles {
            guard let id = pdfFile.libraryID else {
                continue
            }

            try enqueue(SyncPDFRecord(id: id, location: nil, tags: nil, deleted: try nextStamp(storageSettings)), storageSettings)
        }

        PDFFileService.remove(pdfFiles, context)
    }

    static func apply(_ syncIndex: SyncIndex, _ context: ModelContext, _ root: URL, _ localURLs: [UUID: URL]? = nil) throws
    {

        let entries = try context.fetch(FetchDescriptor<PDFFile>())

        var byID = Dictionary(entries.compactMap {
            pdfFile in

            pdfFile.libraryID.map { ($0, pdfFile) }
        }, uniquingKeysWith: {
            first, _ in first
        })

        let removedIDs = Set(syncIndex.files.filter {
            $0.isDeleted || (localURLs != nil && localURLs?[$0.id] == nil)
        }.map(\.id))

        let deleted = entries.filter {
            pdfFile in

            guard let id = pdfFile.libraryID else {
                return false
            }

            return removedIDs.contains(id)
        }

        PDFTagService.deleteTagsOrphanedByDeleting(deleted, context)

        for pdfFile in deleted {

            byID[pdfFile.libraryID!] = nil
            context.delete(pdfFile)

        }

        var tags = try PDFTagService.tagsByName(context).filter {
            !$0.value.isDeleted
        }

        let store = SyncFileStore(root: root)

        for record in syncIndex.files where !removedIDs.contains(record.id) {

            guard let location = record.location else {
                continue
            }

            let url = try localURLs?[record.id] ?? store.fileURL(location.relativePath)

            let pdfFile = byID[record.id] ?? PDFFile(url, nil, location.addedAt)

            if pdfFile.modelContext == nil {

                context.insert(pdfFile)

                byID[record.id] = pdfFile

            }

            if pdfFile.url != url || pdfFile.syncContentHash != location.contentHash {

                pdfFile.url = url

                pdfFile.bookmarkData = nil

                pdfFile.searchableText = nil

                pdfFile.contentFingerprint = nil
            }

            pdfFile.libraryID = record.id

            pdfFile.addedAt = location.addedAt

            pdfFile.syncRelativePath = localURLs == nil ? location.relativePath : nil

            pdfFile.syncContentHash = localURLs == nil ? location.contentHash : nil

            pdfFile.syncBaselineContentHash = location.contentHash

            pdfFile.syncBaselineTags = try JSONEncoder().encode(record.tags?.names ?? [])

            if pdfFile.bookmarkData == nil, FileManager.default.fileExists(atPath: url.path) {

                pdfFile.bookmarkData = try URL.securityScopedBookmarkData(url)

            }

            let selectedTags = PDFTagService.resolveTags(record.tags?.names ?? [], context, &tags)

            if pdfFile.tags.map(\.normalizedName).sorted() != selectedTags.map(\.normalizedName).sorted() {

                pdfFile.tags = selectedTags

            }
        }

        for tag in tags.values where tag.pdfFiles.isEmpty {
            context.delete(tag)
        }

    }

    static func applyRefresh(_ syncIndex: SyncIndex, _ context: ModelContext, _ root: URL, _ storageSettings: StorageSettings, _ sentData: Data?) throws {
        let merged = syncIndex.merging(try pendingChanges(storageSettings))

        try apply(merged, context, root)

        storageSettings.syncCounter = max(storageSettings.syncCounter, merged.counter)

        if storageSettings.pendingSyncChanges == sentData {
            storageSettings.pendingSyncChanges = nil
        }
    }

    static func pendingChanges(_ storageSettings: StorageSettings) throws -> SyncIndex {
        try storageSettings.pendingSyncChanges.map(SyncIndex.decode) ?? SyncIndex()
    }

    private static func enqueue(_ record: SyncPDFRecord, _ storageSettings: StorageSettings) throws {
        storageSettings.pendingSyncChanges = try pendingChanges(storageSettings).merging( SyncIndex( files: [record] ) ).encoded()
    }

    private static func nextStamp(_ storageSettings: StorageSettings) throws -> SyncStamp {
        
        guard storageSettings.syncCounter < Int64.max - 1 else {
            throw SyncStoreError.invalidIndex
        }
        
        if storageSettings.syncDeviceID == nil {
            storageSettings.syncDeviceID = UUID()
        }
        
        storageSettings.syncCounter += 1
        
        return SyncStamp( counter: storageSettings.syncCounter, deviceID: storageSettings.syncDeviceID!, operationID: UUID() )
    }
}
