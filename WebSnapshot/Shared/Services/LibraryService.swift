import Combine
import CryptoKit
import Foundation
import PDFKit
import SwiftData

@MainActor
enum LibraryService {
    static func savePDF(_ data: Data, _ fileName: String, _ context: ModelContext, _ settings: [StorageSettings], sync:LibrarySyncService, chooseDestination: ((String) -> URL?)? = nil) throws -> URL? {
        
        try sync.requireReady()
        
        if LibrarySyncService.isEnabled(context) {
            return try sync.savePDF(data, fileName, context)
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
                try sync.registerPDF(url, context)
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
            let data = try SyncIndexStore.coordinatedRead(source) {
                try Data(contentsOf: $0)
            }
            
            
            return try sync.savePDF(data, source.lastPathComponent, context)
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
            try sync.deletePDF(url, context)
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
            
            try sync.queueTags(PDFTagService.tagNames(pdf.tags), previous: previous, pdf, context)
            
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

    static func update(_ context: ModelContext, _ message: String,_ operation: () throws -> Bool) throws {
        
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
final class LibrarySyncService: ObservableObject {

    @Published private(set) var state = LibrarySyncState()
    
    private var isRefreshing = false
    
    private var modeGeneration: UInt64 = 0
    
    static func settings(_ context: ModelContext) throws -> StorageSettings? {
    
        guard context.container.schema.entities.contains(where: {
            $0.name == "StorageSettings"
        }) else {
            return nil
        }
    
        return try context.fetch(FetchDescriptor<StorageSettings>()).first
    }

    static func isEnabled(_ context: ModelContext) -> Bool {
        ( try? settings(context) )?.syncEnabled == true
    }

    func requireReady() throws {
        if state.isSwitching {
            throw AppError.error("Wait for the library migration to finish before making changes.")
        }
    }

    static func localStorageURL(_ setting: StorageSettings) throws -> URL? {
        
        guard setting.previousStorageRawValue == StorageSettings.Storage.fixed.rawValue, let bookmark = setting.previousFixedStorageBookmarkData else {
            
            return nil
            
        }
        
        return try resolveBookmarkedURL(bookmark)
    }

    func setEnabled(_ enabled: Bool, _ context: ModelContext, drive: URL? = nil, localRoot: URL? = nil) async throws {
        try requireReady()
        
        guard Self.isEnabled(context) != enabled else {
            return
        }
        
        modeGeneration &+= 1
        
        state.isSwitching = true
        
        state.lastError = nil
        
        defer {
            state.isSwitching = false
        }
        
        do {
            try context.save()
            
            if enabled {
                try await enable(context, drive)
            }
            
            else {
                try await disable(context,  localRoot)
            }
            
        } catch {
            context.rollback()
            
            state.lastError = AppError(error)
            
            throw error
        }
    }

    func reconnect(_ selected: URL, _ context: ModelContext) throws {
        let accessing = selected.startAccessingSecurityScopedResource()

        defer {

            if accessing {
                selected.stopAccessingSecurityScopedResource()
            }
        }

        do {
            try requireReady()

            guard let setting = try Self.settings(context) else {
                return
            }

            let drive = try SyncIndexStore.cloudDrive(selected)

            let folder = try SyncIndexStore.cloudFolder(drive)

            if let savedPath = setting.syncDrivePath, URL(fileURLWithPath: savedPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL != drive.resolvingSymlinksInPath().standardizedFileURL {

                throw SyncStoreError.wrongDrive

            }

            setting.syncDriveBookmarkData = try URL.securityScopedBookmarkData(drive)

            setting.syncDrivePath = drive.path

            if FileManager.default.fileExists(atPath: folder.path) {
                let bookmark = try URL.securityScopedBookmarkData(folder)

                setting.syncFolderBookmarkData = bookmark

                if setting.syncEnabled { setting.fixedStorageBookmarkData = bookmark }
            }

            try context.save()

        } catch {
            context.rollback()
            throw error
        }
    }

    private func enable(_ context: ModelContext, _ selectedDrive: URL?) async throws {
        
        let setting = try Self.settings(context) ?? StorageSettings(.flexibility)
        
        if setting.modelContext == nil {
            context.insert(setting)
        }
        
        let drive = try selectedDrive.map(SyncIndexStore.cloudDrive) ?? driveURL(setting)
        let accessing = drive.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
                
                drive.stopAccessingSecurityScopedResource()
            
            }
        
        }
        
        let root = try SyncIndexStore.prepareCloudFolder(drive)
        
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
        
        let local = try pdfs.map {
            pdf in
            
            SyncLocalPDF(id: pdf.libraryID!, url: try pdf.resolveURL(), addedAt: pdf.addedAt, tagNames: PDFTagService.tagNames(pdf.tags), sharedHash: pdf.syncBaselineContentHash, baselineTags: try pdf.syncBaselineTags.map {
                try JSONDecoder().decode([String].self, from: $0)
            })
            
        }
        
        let deviceID = setting.syncDeviceID!
        
        let counter = setting.syncCounter
        
        let index = try await Task.detached(priority: .userInitiated) {
        
            try SyncIndexStore(root: root).prepareEnable(local, deviceID, counter)
        
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

    private func disable(_ context: ModelContext, _ localRoot: URL?) async throws {
        
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
        
        let pending = try pendingChanges(setting)
        
        guard let destination = try localRoot ?? Self.localStorageURL(setting) else {
            throw AppError.error("Choose a storage folder before turning Sync off.")
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
            
            try SyncIndexStore(root: root).prepareDisable(pending,  destination)
            
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

    private func importFixedStorage(_ context: ModelContext, _ directory: URL) throws {
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
            
            let pending = try pendingChanges(setting)
            
            let index = try await Task.detached(priority: .utility) {
                
                let store = SyncIndexStore(root: root)
                
                try store.publish(pending)
                
                let index = try store.load().merging(pending)
                
                try store.writeSnapshot(index)
            
                return index
            }.value
            
            
            
            guard generation == modeGeneration, !state.isSwitching, Self.isEnabled(context), !Task.isCancelled else {
                return
            }
            
            
            
            let merged = index.merging( try pendingChanges(setting) )
            
            try LibrarySyncRepository.apply(merged, context, root)
            
            setting.syncCounter = max(setting.syncCounter, merged.counter)
            
            if setting.pendingSyncChanges == sentData {
                setting.pendingSyncChanges = nil
            }
            
            if context.hasChanges {
                try context.save()
            }
            
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

    func savePDF(_ data: Data, _ fileName: String, _ context: ModelContext) throws -> URL {
        
        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled else {
            throw AppError.error("Sync is not enabled.")
        }
        
        let root = try folderURL(setting)
        
        let accessing = root.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
                root.stopAccessingSecurityScopedResource()
            }
        }
        
        let id = UUID()
        
        let hash = SHA256.hash( data: data).map {
            
            String(format: "%02x", $0)
        
        }.joined()
        
        let path = "PDFs/\(id.uuidString)/\(hash)/\(URL(fileURLWithPath: fileName).lastPathComponent)"
        
        let destination = try SyncIndexStore(root: root).fileURL(path)
        
        try FileManager.default.createDirectory( at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        try SyncIndexStore.coordinatedWrite(destination) {
            try data.write( to: $0,  options: .atomic)
        }
        
        do {
            try LibraryService.update(context, "The PDF could not be added to the library.") {
                try registerPDF(destination, context, id: id, hash: hash)
                
                return true
            }
        }catch {
            
            try? SyncIndexStore.coordinatedWrite(destination) {
                try FileManager.default.removeItem( at: $0)
            }
            
            throw error
        }
        
        return destination
    }

    func registerPDF(_ url: URL, _ context: ModelContext, id: UUID? = nil, hash: String? = nil) throws {
        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled else {
            return
        }
        
        let root = try folderURL(setting)
        
        let accessing = root.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
            
                root.stopAccessingSecurityScopedResource()
            
            }
        
        }
        
        
        let base = root.standardizedFileURL.path + "/"
        
        guard url.standardizedFileURL.path.hasPrefix(base) else {
            throw SyncStoreError.unsafePath
        }
        
        
        let path = String(url.standardizedFileURL.path.dropFirst(base.count))
        
        _ = try SyncIndexStore(root: root).fileURL(path)
        
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
        
        pdf.syncContentHash = try hash ?? SyncIndexStore.contentHash(url)
        
        pdf.syncBaselineContentHash = pdf.syncContentHash
        
        pdf.syncBaselineTags = try JSONEncoder().encode(PDFTagService.tagNames(pdf.tags))
        
        pdf.searchableText = nil
        
        pdf.contentFingerprint = nil
        
        let stamp = try nextStamp(setting)
        
        let record = SyncPDFRecord( id: pdf.libraryID!, location: SyncPDFLocation(relativePath: path, contentHash: pdf.syncContentHash!, addedAt: pdf.addedAt, stamp: stamp ), tags: SyncPDFTags(PDFTagService.tagNames(pdf.tags), stamp), deleted: nil)
        
        try enqueue(record, setting)
        
    }

    func queueTags(_ names: [String], previous: [String], _ pdf: PDFFile, _ context: ModelContext) throws {
       
        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled, let id = pdf.libraryID else {
            return
        }
        
        try enqueue( SyncPDFRecord( id: id, location: nil, tags: SyncPDFTags(editing: names, previous: previous, try nextStamp(setting) ), deleted: nil ), setting)
        
        pdf.syncBaselineTags = try JSONEncoder().encode(names)
        
    }

    func deletePDF(_ url: URL, _ context: ModelContext) throws {
        
        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled else {
            return
        }
        
        let root = try folderURL(setting)
        
        var sources: Set<URL> = []
        
        try LibraryService.update(context, "The PDF could not be removed from the library.") {
            let pdfs = try PDFFileService.entries(context, matching: url).filter {
                $0.libraryID != nil
            }
            
            for pdf in pdfs {
                if let path = pdf.syncRelativePath, let source = try? SyncIndexStore(root: root).fileURL(path) {
                    sources.insert(source)
                }
                
                try enqueue(SyncPDFRecord(id: pdf.libraryID!, location: nil, tags: nil, deleted: try nextStamp(setting)), setting)
            }
            
            PDFFileService.remove(pdfs, context)
            
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
                
                try SyncIndexStore.coordinatedWrite(source) {
                
                    if FileManager.default.fileExists(atPath: $0.path) {
                        
                        try FileManager.default.removeItem( at: $0)
                        
                    }
                
                }
                
            } catch {
                state.lastError = AppError(error)
            }
            
        }
        
    }

    func download(_ pdf: PDFFile, _ context: ModelContext) async throws {
        
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

        let accessingFile = url.startAccessingSecurityScopedResource()

        defer {
            if accessingFile {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        try await Task.detached(priority: .userInitiated) {
            
            _ = try SyncIndexStore.coordinatedRead(url) {
                
                try FileHandle(forReadingFrom: $0).close()
            
            }
            
        }.value
        
        
        guard generation == modeGeneration, pdf.modelContext != nil, !pdf.isDeleted, pdf.url == storedURL, !state.isSwitching, Self.isEnabled(context), try pdf.resolveURL() == url else {
            
            throw AppError.error("The library changed during the download. Open the PDF again.")
            
        }
        
        pdf.bookmarkData = try URL.securityScopedBookmarkData(url)
        
        try context.save()
    }

    func folderURL(_ setting: StorageSettings) throws -> URL {
        
        guard let bookmark = setting.syncFolderBookmarkData else {
        
            throw AppError.permissionDenied("Reconnect the websnapshot folder in Settings to resume Sync.")
        
        }
        
        
        var stale = false
        
        let root = try URL.resolveSecurityScopedBookmarkData(bookmark, &stale)
        
        guard root.lastPathComponent == "websnapshot", let savedPath = setting.syncFolderPath, root.resolvingSymlinksInPath().standardizedFileURL == URL(fileURLWithPath: savedPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL else {
            
            throw AppError.permissionDenied("Reconnect iCloud Drive/websnapshot in Settings to resume Sync.")
            
        }
        
        return root
    }

    private func driveURL(_ setting: StorageSettings) throws -> URL {
        guard let bookmark = setting.syncDriveBookmarkData, let savedPath = setting.syncDrivePath else {
            throw AppError.permissionDenied("Allow access to iCloud Drive in Settings to turn on Sync.")
        }
        
        var stale = false
        
        let drive = try URL.resolveSecurityScopedBookmarkData(bookmark, &stale)
        
        _ = try SyncIndexStore.cloudDrive(drive)
        
        guard drive.resolvingSymlinksInPath().standardizedFileURL == URL(fileURLWithPath: savedPath, isDirectory: true).resolvingSymlinksInPath().standardizedFileURL else {
            
            throw AppError.permissionDenied("Reconnect iCloud Drive in Settings to turn on Sync.")
            
        }
        
        return drive
    }

    private func pendingChanges(_ setting: StorageSettings) throws -> SyncIndex {
        try setting.pendingSyncChanges.map(SyncIndex.decode) ?? SyncIndex()
    }

    private func enqueue(_ record: SyncPDFRecord, _ setting: StorageSettings) throws {
        setting.pendingSyncChanges = try pendingChanges(setting).merging( SyncIndex( files: [record] ) ).encoded()
    }

    private func nextStamp(_ setting: StorageSettings) throws -> SyncStamp {
        
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

@MainActor
enum LibrarySyncRepository {
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

        let store = SyncIndexStore(root: root)

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

}

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
