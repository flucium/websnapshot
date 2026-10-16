import AppKit
import CryptoKit
import Foundation
import SwiftData

@MainActor
final class LibrarySyncService {

    let state = LibrarySyncState()
    
    private var isRefreshing = false
    
    private var modeGeneration: UInt64 = 0
    
    static let shared = LibrarySyncService()
    
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
            
            SyncLocalPDF(id: pdf.libraryID!, url: try pdf.resolveURL(), addedAt: pdf.addedAt, tagNames: PDFTagService.tagNames(pdf.tags), sharedPath: pdf.syncRelativePath,sharedHash: pdf.syncBaselineContentHash, baselineTags: try pdf.syncBaselineTags.map {
                try JSONDecoder().decode([String].self, from: $0)
            })
            
        }
        
        let deviceID = setting.syncDeviceID!
        
        let counter = setting.syncCounter
        
        let index = try await Task.detached(priority: .userInitiated) {
        
            try SyncIndexStore(root: root).prepareEnable(local, deviceID, counter)
        
        }.value
        
        try Task.checkCancellation()
        
        try apply(index, context, root)
        
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
        
        try apply(index, context,  root, urls)
        
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
            
            try apply(merged, context, root)
            
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
            try registerPDF(destination, context, id: id, hash: hash)
        }catch {
         
            context.rollback()
            
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
        
        try context.save()
        
    }

    func queueTags(_ names: [String], previous: [String], _ pdf: PDFFile, _ context: ModelContext) throws {
       
        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled, let id = pdf.libraryID else {
            return
        }
        
        try enqueue( SyncPDFRecord( id: id, location: nil, tags: SyncPDFTags(editing: names, previous: previous, try nextStamp(setting) ), deleted: nil ), setting)
        
        pdf.syncBaselineTags = try JSONEncoder().encode(names)
        
    }

    func deletePDF(_ pdf: PDFFile, _ context: ModelContext) throws {
        
        try requireReady()
        
        guard let setting = try Self.settings(context), setting.syncEnabled, let id = pdf.libraryID else {
            return
        }
        
        let root = try folderURL(setting)
        
        let source = pdf.syncRelativePath.map {
            
            try? SyncIndexStore(root: root).fileURL($0)
        
        } ?? nil
        
        try enqueue( SyncPDFRecord( id: id, location: nil,  tags: nil,  deleted: try nextStamp(setting) ), setting)
        
        PDFTagService.deleteTagsOrphanedByDeleting([pdf],  context)
        
        context.delete(pdf)
        
        try context.save()
        
        if let source {
            
            let accessing = root.startAccessingSecurityScopedResource()
            
            defer {
                
                if accessing {
                    
                    root.stopAccessingSecurityScopedResource()
                
                }
            
            }
            
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

    private func apply(_ index: SyncIndex, _ context: ModelContext, _ root: URL, _ localURLs: [UUID: URL]? = nil) throws {
        
        let entries = try context.fetch( FetchDescriptor<PDFFile>() )
        
        var byID: [UUID: PDFFile] = Dictionary(entries.compactMap {
            
            pdf in pdf.libraryID.map {
                
                ($0, pdf)
            
            }
        
        }, uniquingKeysWith: {
            first, _ in first
        })
        
        var tags: [String: PDFTag] = Dictionary(try context.fetch(FetchDescriptor<PDFTag>()).map { ($0.normalizedName, $0) }, uniquingKeysWith: { first, _ in first })
        
        
        let deleted = entries.filter { pdf in
            
            guard let id = pdf.libraryID else {
                return false
            }
            
            return index.files.contains {
                $0.id == id && $0.isDeleted
            }
        }
        
        PDFTagService.deleteTagsOrphanedByDeleting(deleted,  context)
        
        for pdf in deleted {
            
            byID[pdf.libraryID!] = nil; context.delete(pdf)
        
        }
        
        tags = tags.filter {
            $0.value.modelContext != nil && !$0.value.isDeleted
        }
        
        
        for record in index.files where !record.isDeleted {
            
            guard let location = record.location else {
                continue
            }
            
            let url = try localURLs?[record.id] ?? SyncIndexStore(root: root).fileURL(location.relativePath)
            
            
            let pdf = byID[record.id] ?? PDFFile(url, nil, location.addedAt)
            
            if pdf.modelContext == nil {
                
                context.insert(pdf);
                
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
            
            var selectedTags: [PDFTag] = []
            
            var seen: Set<String> = []
            
            for name in record.tags?.names ?? [] {
            
                let normalized = PDFTagService.normalizedName(name)
                
                guard !normalized.isEmpty, seen.insert(normalized).inserted else {
                    continue
                }
                
                let tag = tags[normalized] ?? PDFTag( PDFTagService.displayName(name),  normalizedName: normalized )
                
                if tag.modelContext == nil {
                    
                    context.insert(tag); tags[normalized] = tag
                
                }
                
                selectedTags.append(tag)
                
            }
            
            if pdf.tags.map(\.normalizedName).sorted() != selectedTags.map(\.normalizedName).sorted() {
         
                pdf.tags = selectedTags
            
            }
        }
        
        for tag in tags.values where tag.pdfFiles.isEmpty {
            context.delete(tag)
        }
        
    }
    
}
