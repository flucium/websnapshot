import Foundation
import PDFKit
import SwiftData

@MainActor
enum LibraryService {
    static func savePDF(_ data: Data, _ fileName: String, _ context: ModelContext, _ settings: [StorageSettings], sync:LibrarySyncService, chooseDestination: ((String) -> URL?)? = nil) throws -> URL? {
        
        try sync.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            return try saveSyncedPDF(data, fileName, context)
        }

        switch StorageSettingsService.storage(settings) {
        case .flexibility:
            guard let destination = chooseDestination?(fileName) else {
                return nil
            }
            
            try refreshLocations(context, sync: sync)
            
            try PDFFileStore.write(data, to: destination) {
                try registerPDF(context, $0, sync: sync)
            }
            
            return destination
            
        case .fixed:
            guard let directory = try StorageSettingsService.fixedStorageURL(settings, sync: sync) else {
                throw AppError.error("Choose a storage folder in Settings before saving.")
            }
            
            let accessing = directory.startAccessingSecurityScopedResource()
            
            defer {
                if accessing {
                    directory.stopAccessingSecurityScopedResource()
                }
            }
            
            try refreshLocations(context, sync: sync)
            
            return try PDFFileStore.save(data, fileName, in: directory) {
                try registerPDF(context, $0, sync: sync)
            }
        }
    }

    static func registerPDF(_ context: ModelContext, _ url: URL, sync: LibrarySyncService) throws {
        try sync.requireReady()
        
        
        try update(context, "The PDF could not be added to the library.") {
            
            if LibrarySyncService.isEnabled(context) {
                try registerSyncedPDF(url, context)
            } else {
                try PDFFileService.register(context, url)
            }
            
            return true
        }
        
    }

    static func importPDF(_ source: URL, _ directory: URL, _ context: ModelContext, sync: LibrarySyncService ) throws -> URL {
        
        try sync.requireReady()
        
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
            try registerPDF(context, source, sync: sync)
            
            return source
        }
        
        do {
            
            return try PDFFileStore.copy(source, to: directory) {
                try registerPDF(context, $0, sync: sync)
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

    static func delete(_ context: ModelContext, _ url: URL, _ resolvedURL: URL, sync: LibrarySyncService, _ removeFile: ((URL) throws -> Void)? = nil ) throws {
        
        try sync.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            try removePDFRecords(context, url, sync: sync)
            return
        }
        
        try (removeFile ?? FileIO.delete)(resolvedURL)
        
        do {
            try removePDFRecords(context, url, sync: sync)
        } catch {
            AppLogger.recordDiagnostic("The file was deleted, but its library entry could not be removed. Automatic synchronization will retry the cleanup.", "Delete PDF library entry", resolvedURL)
            
            throw error
            
        }
    }

    static func removePDFRecords(_ context: ModelContext, _ url: URL, sync: LibrarySyncService) throws {
        try sync.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            try removeSyncedPDFRecords(context, url, sync: sync)
            return
        }
        
        try update(context, "The PDF could not be removed from the library.") {
            
            let matched = try PDFFileService.entries(context, matching: url)
        
            PDFFileService.remove(matched, context)
            
            return !matched.isEmpty
        }
    }

    static func replaceTags(_ names: [String], _ pdf: PDFFile, _ context: ModelContext,sync: LibrarySyncService) throws {
        
        try sync.requireReady()
        
        guard pdf.modelContext != nil, !pdf.isDeleted else {
            throw AppError.error("This PDF is no longer in the library.")
        }
        
        let previous = PDFTagService.tagNames(pdf.tags)
        
        try update(context, "The tags could not be saved.") {
        
            try PDFTagService.replaceTags(names, pdf, context)
            
            if let setting = try LibrarySyncSettings.settings(context), setting.syncEnabled {
                try LibrarySyncRepository.queueTags(PDFTagService.tagNames(pdf.tags), previous: previous, pdf, setting)
            }
            
            return true
        }
    }

    static func refreshLocations(_ context: ModelContext, sync: LibrarySyncService) throws {
        try sync.requireReady()
        
        guard !LibrarySyncService.isEnabled(context) else {
            return
        }
        
        try update(context, "The library's file locations could not be updated before saving.") {
            try PDFFileService.refreshLocations(context)
        }
    }

    static func deleteMissingFiles(_ context: ModelContext, _ pdfs: [PDFFile], sync: LibrarySyncService,_ confirmedDeletedIDs: Set<PersistentIdentifier> = []) throws {
        
        guard !sync.state.isSwitching, !LibrarySyncService.isEnabled(context) else {
            return
        }
        
        try update(context, "The library could not be synchronized.") {
            PDFFileService.deleteMissingFiles(context, pdfs, confirmedDeletedIDs)
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

    private static func removeSyncedPDFRecords(_ context: ModelContext, _ url: URL, sync: LibrarySyncService) throws {
        guard let setting = try LibrarySyncSettings.settings(context), setting.syncEnabled else {
            return
        }

        let root = try LibrarySyncSettings.folderURL(setting)
        let files = SyncFileStore(root: root)
        var sources: Set<URL> = []

        try update(context, "The PDF could not be removed from the library.") {
            let pdfs = try PDFFileService.entries(context, matching: url).filter {
                $0.libraryID != nil
            }

            for pdf in pdfs {
                if let path = pdf.syncRelativePath, let source = try? files.fileURL(path) {
                    sources.insert(source)
                }
            }

            try LibrarySyncRepository.remove(pdfs, context, setting)

            return !pdfs.isEmpty
        }

        let accessing = root.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                root.stopAccessingSecurityScopedResource()
            }
        }

        for source in sources {
            do {
                try SyncFileStore.remove(source)
            } catch {
                sync.reportError(error)
            }
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
    static func localPDFs(_ pdfs: [PDFFile]) throws -> [SyncLocalPDF] {
        try pdfs.map {
            pdf in
            
            SyncLocalPDF(id: pdf.libraryID!, url: try pdf.resolveURL(), addedAt: pdf.addedAt, tagNames: PDFTagService.tagNames(pdf.tags), sharedHash: pdf.syncBaselineContentHash, baselineTags: try pdf.syncBaselineTags.map {
                try JSONDecoder().decode([String].self, from: $0)
            })
            
        }
    }

    static func registerPDF(_ url: URL, _ context: ModelContext, _ setting: StorageSettings, _ path: String, _ hash: String, id: UUID? = nil) throws {
        let entries = try context.fetch( FetchDescriptor<PDFFile>() )
        
        
        let pdf = entries.first {
            $0.url.standardizedFileURL == url.standardizedFileURL
        } ?? PDFFile( url, nil, Date() )
        
        if pdf.modelContext == nil {
            
            context.insert(pdf)
        
        }
        
        
        pdf.libraryID = pdf.libraryID ?? id ?? UUID()
        
        pdf.url = url
        
        pdf.bookmarkData = try URL.securityScopedBookmarkData(url)
        
        pdf.syncRelativePath = path
        
        pdf.syncContentHash = hash
        
        pdf.syncBaselineContentHash = pdf.syncContentHash
        
        pdf.syncBaselineTags = try JSONEncoder().encode(PDFTagService.tagNames(pdf.tags))
        
        pdf.searchableText = nil
        
        pdf.contentFingerprint = nil
        
        let stamp = try nextStamp(setting)
        
        let record = SyncPDFRecord( id: pdf.libraryID!, location: SyncPDFLocation(relativePath: path, contentHash: pdf.syncContentHash!, addedAt: pdf.addedAt, stamp: stamp ), tags: SyncPDFTags(PDFTagService.tagNames(pdf.tags), stamp), deleted: nil)
        
        try enqueue(record, setting)
        
    }

    static func queueTags(_ names: [String], previous: [String], _ pdf: PDFFile, _ setting: StorageSettings) throws {
        guard let id = pdf.libraryID else {
            return
        }

        try enqueue( SyncPDFRecord( id: id, location: nil, tags: SyncPDFTags(editing: names, previous: previous, try nextStamp(setting) ), deleted: nil ), setting)
        
        pdf.syncBaselineTags = try JSONEncoder().encode(names)
        
    }

    static func remove(_ pdfs: [PDFFile], _ context: ModelContext, _ setting: StorageSettings) throws {
        for pdf in pdfs {
            guard let id = pdf.libraryID else {
                continue
            }

            try enqueue(SyncPDFRecord(id: id, location: nil, tags: nil, deleted: try nextStamp(setting)), setting)
        }

        PDFFileService.remove(pdfs, context)
    }

    static func apply(_ index: SyncIndex, _ context: ModelContext, _ root: URL, _ localURLs: [UUID: URL]? = nil) throws
    {

        let entries = try context.fetch(FetchDescriptor<PDFFile>())

        var byID = Dictionary(entries.compactMap {
            pdf in

            pdf.libraryID.map { ($0, pdf) }
        }, uniquingKeysWith: {
            first, _ in first
        })

        let deletedIDs = Set(index.files.filter(\.isDeleted).map(\.id))

        let deleted = entries.filter { pdf in

            guard let id = pdf.libraryID else {
                return false
            }

            return deletedIDs.contains(id)
        }

        PDFTagService.deleteTagsOrphanedByDeleting(deleted, context)

        for pdf in deleted {

            byID[pdf.libraryID!] = nil
            context.delete(pdf)

        }

        var tags = try PDFTagService.tagsByName(context).filter {
            !$0.value.isDeleted
        }

        let store = SyncFileStore(root: root)

        for record in index.files where !record.isDeleted {

            guard let location = record.location else {
                continue
            }

            let url = try localURLs?[record.id] ?? store.fileURL(location.relativePath)

            let pdf = byID[record.id] ?? PDFFile(url, nil, location.addedAt)

            if pdf.modelContext == nil {

                context.insert(pdf)

                byID[record.id] = pdf

            }

            if pdf.url != url || pdf.syncContentHash != location.contentHash {

                pdf.url = url

                pdf.bookmarkData = nil

                pdf.searchableText = nil

                pdf.contentFingerprint = nil
            }

            pdf.libraryID = record.id

            pdf.addedAt = location.addedAt

            pdf.syncRelativePath = localURLs == nil ? location.relativePath : nil

            pdf.syncContentHash = localURLs == nil ? location.contentHash : nil

            pdf.syncBaselineContentHash = location.contentHash

            pdf.syncBaselineTags = try JSONEncoder().encode(record.tags?.names ?? [])

            if pdf.bookmarkData == nil, FileManager.default.fileExists(atPath: url.path) {

                pdf.bookmarkData = try URL.securityScopedBookmarkData(url)

            }

            let selectedTags = PDFTagService.resolveTags(record.tags?.names ?? [], context, &tags)

            if pdf.tags.map(\.normalizedName).sorted() != selectedTags.map(\.normalizedName).sorted() {

                pdf.tags = selectedTags

            }
        }

        for tag in tags.values where tag.pdfFiles.isEmpty {
            context.delete(tag)
        }

    }

    static func applyRefresh(_ index: SyncIndex, _ context: ModelContext, _ root: URL, _ setting: StorageSettings, _ sentData: Data?) throws {
        let merged = index.merging(try pendingChanges(setting))

        try apply(merged, context, root)

        setting.syncCounter = max(setting.syncCounter, merged.counter)

        if setting.pendingSyncChanges == sentData {
            setting.pendingSyncChanges = nil
        }
    }

    static func pendingChanges(_ setting: StorageSettings) throws -> SyncIndex {
        try setting.pendingSyncChanges.map(SyncIndex.decode) ?? SyncIndex()
    }

    private static func enqueue(_ record: SyncPDFRecord, _ setting: StorageSettings) throws {
        setting.pendingSyncChanges = try pendingChanges(setting).merging( SyncIndex( files: [record] ) ).encoded()
    }

    private static func nextStamp(_ setting: StorageSettings) throws -> SyncStamp {
        
        guard setting.syncCounter < Int64.max - 1 else {
            throw SyncStoreError.invalidIndex
        }
        
        if setting.syncDeviceID == nil {
            setting.syncDeviceID = UUID()
        }
        
        setting.syncCounter += 1
        
        return SyncStamp( counter: setting.syncCounter, deviceID: setting.syncDeviceID!, operationID: UUID() )
    }
}
