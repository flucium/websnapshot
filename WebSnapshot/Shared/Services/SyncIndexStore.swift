import Foundation
import CryptoKit

nonisolated enum SyncStoreError: Error, LocalizedError {
    
    case unsupportedSchema, invalidIndex, unsafePath, unavailableFile, wrongFolder, wrongDrive

    var errorDescription: String? {
        switch self {
        case .unsupportedSchema: "This library was created by a newer version of WebSnapshot. Update the app before syncing."
        case .invalidIndex: "The sync index could not be read. The existing library has been preserved."
        case .unsafePath: "The sync index contains a file path outside the library folder."
        case .unavailableFile: "A PDF is not available locally. Download it from iCloud Drive and try again."
        case .wrongFolder: "Choose iCloud Drive itself or its websnapshot folder."
        case .wrongDrive: "Choose iCloud Drive itself. WebSnapshot creates its websnapshot folder automatically."
        }
    }
}

nonisolated struct SyncIndexStore: Sendable {
    var root: URL

    struct Cache: Sendable {
        fileprivate var root: URL?

        fileprivate var metadata: [URL: SyncIndex] = [:]

        fileprivate var fingerprints: [URL: String] = [:]

        fileprivate var index = SyncIndex()

        fileprivate var contents: [URL: (fingerprint: String, hash: String)] = [:]

        mutating func contentHash(_ url: URL) throws -> String {
            let fingerprint = try Self.fingerprint(url)

            if let cached = contents[url], cached.fingerprint == fingerprint {
                return cached.hash
            }

            let hash = try SyncFileStore.contentHash(url)

            if try Self.fingerprint(url) == fingerprint {
                contents[url] = (fingerprint, hash)
            }

            return hash
        }

        fileprivate static func fingerprint(_ url: URL) throws -> String {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

            guard let date = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? NSNumber,
                  let inode = attributes[.systemFileNumber] as? NSNumber else {
                throw SyncStoreError.unavailableFile
            }

            return "\(date.timeIntervalSince1970):\(size):\(inode)"
        }
    }

    func load() throws -> SyncIndex {
        var cache = Cache()

        return try load(&cache)
    }

    func load(_ cache: inout Cache) throws -> SyncIndex {
        if cache.root != root.standardizedFileURL {
            cache = Cache(root: root.standardizedFileURL)
        }

        var sources: [URL] = []

        let files = SyncFileStore(root: root)

        let indexURL = try files.containedURL("index.json")
        
        if try SyncFileStore.isPresent(indexURL) {
            sources.append(indexURL)

            sources.append(contentsOf: (NSFileVersion.unresolvedConflictVersionsOfItem(at: indexURL) ?? []).map(\.url))
        }
        
        let changes = try files.containedURL("changes")
        
        
        if try SyncFileStore.isPresent(changes) {
            
            let urls = try SyncFileStore.coordinatedRead(changes) {
            
                directory in
                
                try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            }
            
            
            sources.append(contentsOf: try urls.compactMap(Self.metadataURL).map {
                try files.containedURL("changes/\($0.lastPathComponent)")
            })
        }

        let sourceURLs = Set(sources)

        var changed = Set(cache.metadata.keys) != sourceURLs

        var metadata = cache.metadata.filter { sourceURLs.contains($0.key) }

        var fingerprints = cache.fingerprints.filter { sourceURLs.contains($0.key) }

        for url in sourceURLs.sorted(by: { $0.path < $1.path }) {
            let fingerprint = try? Cache.fingerprint(url)

            if let fingerprint, fingerprints[url] == fingerprint, metadata[url] != nil {
                continue
            }

            metadata[url] = try SyncIndex.decode(read(url))

            let currentFingerprint = try? Cache.fingerprint(url)

            fingerprints[url] = currentFingerprint == fingerprint ? currentFingerprint : nil

            changed = true
        }

        let index = changed ? SyncIndex(files: metadata.values.flatMap(\.files)).merging(SyncIndex()) : cache.index
        
        for record in index.files {
        
            if let path = record.location?.relativePath {
                _ = try SyncFileStore(root: root).fileURL(path)
            }
        
        }

        cache.metadata = metadata

        cache.fingerprints = fingerprints

        cache.index = index
        
        return index
    }

    func publish(_ changes: SyncIndex) throws {
        
        guard !changes.files.isEmpty else {
            return
        }
        
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        let files = SyncFileStore(root: root)

        let directory = try files.containedURL("changes")
        
        try FileManager.default.createDirectory( at: directory, withIntermediateDirectories: true)
        
        
        let stamps = changes.files.flatMap {
            [$0.location?.stamp, $0.tags?.stamp, $0.deleted]
        }.compactMap {
            $0
        }
        
        
        guard let stamp = stamps.max() else {
            throw SyncStoreError.invalidIndex
        }
        
        
        let url = try files.containedURL("changes/\(stamp.deviceID.uuidString)-\(stamp.operationID.uuidString).json")
        
        
        let data = try changes.encoded()
        
        try SyncFileStore.coordinatedWrite(url) {
            
            destination in
            
            if FileManager.default.fileExists( atPath: destination.path) {
                
                guard try Data( contentsOf: destination) == data else {
                    
                    throw SyncStoreError.invalidIndex
                
                }
                
                
            } else {
                
                try data.write(to: destination, options: .atomic)
                
            }
            
        }
        
    }

    func writeSnapshot(_ index: SyncIndex) throws {
        
        let url = try SyncFileStore(root: root).containedURL("index.json")
        
        let data = try index.encoded()
        
        if try SyncFileStore.isPresent(url), try read(url) == data {
            return
        }
        
        try SyncFileStore.coordinatedWrite(url) {
            try data.write( to: $0, options: .atomic)
        }
    }

    func writeSnapshot(_ index: SyncIndex, _ cache: inout Cache) throws {
        let url = try SyncFileStore(root: root).containedURL("index.json")

        if cache.root != root.standardizedFileURL {
            cache = Cache(root: root.standardizedFileURL)
        }

        if cache.root == root.standardizedFileURL, cache.metadata[url] == index,
           let fingerprint = try? Cache.fingerprint(url), cache.fingerprints[url] == fingerprint {
            return
        }

        try writeSnapshot(index)

        cache.metadata[url] = index

        cache.fingerprints[url] = nil

        cache.index = SyncIndex(files: cache.metadata.values.flatMap(\.files)).merging(SyncIndex())
    }

    private static func metadataURL(_ url: URL) -> URL? {
        
        if url.pathExtension == "json" {
            return url
        }
        
        let name = url.lastPathComponent
        
        guard name.hasPrefix("."), name.hasSuffix(".json.icloud") else {
            return nil
        }
        
        return url.deletingLastPathComponent().appendingPathComponent(String(name.dropFirst().dropLast(".icloud".count)))
    }

    private func read(_ url: URL) throws -> Data {
        try SyncFileStore.coordinatedRead(url) {
            try Data( contentsOf: $0)
        }
    }
}

nonisolated struct SyncFileStore: Sendable {
    var root: URL

    static var defaultCloudDriveURL: URL {
        let home = FileManager.default.homeDirectory(forUser: NSUserName()) ?? FileManager.default.homeDirectoryForCurrentUser
        
        return home.appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
    }

    static func cloudDrive(_ selection: URL) throws -> URL {
        
        let selected = selection.resolvingSymlinksInPath().standardizedFileURL
        
        guard Array(selected.pathComponents.suffix(2)) == ["Mobile Documents", "com~apple~CloudDocs"] else {
            throw SyncStoreError.wrongDrive
        }

        return selection
    }

    static func cloudFolder(_ selection: URL) throws -> URL {
        
        let selected = selection.resolvingSymlinksInPath().standardizedFileURL
        
        let components = selected.pathComponents
        
        let driveSuffix = ["Mobile Documents", "com~apple~CloudDocs"]
        
        if Array(components.suffix(2)) == driveSuffix {
            
            let folder = selected.appendingPathComponent("websnapshot", isDirectory: true)
            
            guard folder.resolvingSymlinksInPath().deletingLastPathComponent() == selected else {
                throw SyncStoreError.wrongFolder
            }
            
            return folder
        }
        
        if selected.lastPathComponent == "websnapshot",
        
            Array(selected.deletingLastPathComponent().pathComponents.suffix(2)) == driveSuffix {
            
            return selected
        }
        
        throw SyncStoreError.wrongFolder
    }

    static func prepareCloudFolder(_ selection: URL) throws -> URL {
        
        let folder = try cloudFolder(selection)
        
        if selection.standardizedFileURL.lastPathComponent != "websnapshot" {
            
            let siblings = try coordinatedRead(selection) {
                try FileManager.default.contentsOfDirectory( at: $0, includingPropertiesForKeys: [.isDirectoryKey] )
            }
            
            if !siblings.contains(where: {
                
                $0.lastPathComponent == "websnapshot"
                
            }), let existing = siblings.first(where: {
                
                $0.lastPathComponent.caseInsensitiveCompare("websnapshot") == .orderedSame
                
            }) {
                
                var error: NSError?
                
                var moveError: Error?
                
                NSFileCoordinator().coordinate(writingItemAt: existing, options: .forMoving, error: &error) {
                    
                    source in
                    
                    do {
                        
                        try FileManager.default.moveItem(at: source, to: folder)
                        
                    }catch {
                        
                        moveError = error
                    
                    }
                
                }
                
                if let error {
                    
                    throw error
                
                }
                
                if let moveError {
                    
                    throw moveError
                
                }
            }
            
        }
        
        try FileManager.default.createDirectory( at: folder, withIntermediateDirectories: true)
        
        return folder
    }

    func fileURL(_ relativePath: String) throws -> URL {

        guard relativePath.lowercased().hasSuffix(".pdf") else {
            throw SyncStoreError.unsafePath
        }

        return try containedURL(relativePath)
    }

    func containedURL(_ relativePath: String) throws -> URL {
        
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        
        
        guard !relativePath.hasPrefix("/"), !components.isEmpty, components.allSatisfy({
            
            !$0.isEmpty && $0 != "." && $0 != ".."
            
        }) else {
        
            throw SyncStoreError.unsafePath
        
        }
        
        let file = root.appendingPathComponent(relativePath).standardizedFileURL
        
        let base = root.resolvingSymlinksInPath().standardizedFileURL.path + "/"
        
        var checked = root.resolvingSymlinksInPath().standardizedFileURL
        
        for component in components {
        
            let next = checked.appendingPathComponent( String(component) )
            
            if let target = try? FileManager.default.destinationOfSymbolicLink( atPath: next.path) {
                
                checked = (target.hasPrefix("/") ? URL( fileURLWithPath: target) : next.deletingLastPathComponent().appendingPathComponent(target)).resolvingSymlinksInPath()
                
            } else {
                checked = next.resolvingSymlinksInPath()
            }
            
            guard checked.standardizedFileURL.path.hasPrefix(base) else {
            
                throw SyncStoreError.unsafePath
                
            }
            
        }
        
        return file
        
    }

    static func relativePath(_ id: UUID, _ hash: String, _ fileName: String) -> String {
        "PDFs/\(id.uuidString)/\(hash)/\(URL(fileURLWithPath: fileName).lastPathComponent)"
    }

    func relativePath(_ url: URL) throws -> String {
        let base = root.standardizedFileURL.path + "/"

        guard url.standardizedFileURL.path.hasPrefix(base) else {
            throw SyncStoreError.unsafePath
        }

        let path = String(url.standardizedFileURL.path.dropFirst(base.count))

        _ = try fileURL(path)

        return path
    }

    func currentLocation(_ location: SyncPDFLocation, preferredURL: URL? = nil, cache: inout SyncIndexStore.Cache) throws -> SyncPDFLocation? {
        let expected = try fileURL(location.relativePath)

        var source = expected

        if let preferredURL, (try? relativePath(preferredURL)) != nil, Self.isLocallyAvailable(preferredURL) {
            source = preferredURL
        } else if !Self.isLocallyAvailable(expected) {
            return nil
        }

        var current = location

        current.relativePath = try relativePath(source)
        current.contentHash = try cache.contentHash(source)

        return current
    }

    func versionedURL(_ id: UUID, _ source: URL, _ hash: String) throws -> URL {
        let path = Self.relativePath(id, hash, source.lastPathComponent)

        var destination = try fileURL(path)

        var suffix = 2

        while try Self.isPresent(destination) {
            if try Self.contentHash(destination) == hash {
                return destination
            }

            destination = try fileURL(Self.relativePath(id, hash, URL.pdfFileName(source.lastPathComponent, nil, " \(suffix)")))
            suffix += 1
        }

        try Self.copy(source, to: destination, expectedHash: hash)

        return destination
    }

    private static func isLocallyAvailable(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .ubiquitousItemDownloadingStatusKey]),
              values.isRegularFile == true, values.ubiquitousItemDownloadingStatus != .notDownloaded else {
            return false
        }

        return FileManager.default.fileExists(atPath: url.path)
    }

    func write(_ data: Data, _ fileName: String, _ id: UUID, register: (URL, String) throws -> Void) throws -> URL {
        let accessing = root.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                root.stopAccessingSecurityScopedResource()
            }
        }

        let hash = SHA256.hash(data: data).map {
            String(format: "%02x", $0)
        }.joined()

        let destination = try fileURL(Self.relativePath(id, hash, fileName))

        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)

        try Self.coordinatedWrite(destination) {
            try data.write(to: $0, options: .atomic)
        }

        do {
            try register(destination, hash)
        } catch {
            try? Self.remove(destination)
            throw error
        }

        return destination
    }

    static func remove(_ url: URL) throws {
        try coordinatedWrite(url) {
            if FileManager.default.fileExists(atPath: $0.path) {
                try FileManager.default.removeItem(at: $0)
            }
        }
    }

    static func download(_ url: URL) throws {
        let accessing = url.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        _ = try coordinatedRead(url) {
            try FileHandle(forReadingFrom: $0).close()
        }
    }

    static func copy(_ source: URL, to destination: URL, expectedHash: String) throws {
        
        if source.standardizedFileURL == destination.standardizedFileURL {
            return
        }
        
        if FileManager.default.fileExists( atPath: destination.path) {
            
            guard try contentHash(destination) == expectedHash else {
                throw SyncStoreError.invalidIndex
            }
            
            return
        }
        
        let accessing = source.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
                
                source.stopAccessingSecurityScopedResource()
            
            }
        
        }
        
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        
        try coordinatedRead(source) {
            
            sourceURL in
            
            try coordinatedWrite(destination) {
                
                target in
                
                let temporary = target.deletingLastPathComponent().appendingPathComponent(".\(UUID().uuidString).partial")
                
                defer {
                    try? FileManager.default.removeItem( at: temporary )
                }
                
                try FileManager.default.copyItem(at: sourceURL, to: temporary)
                
                guard try contentHash(temporary) == expectedHash else {
                    throw SyncStoreError.invalidIndex
                }
                
                try FileManager.default.moveItem(at: temporary, to: target)
            }
        }
    }

    static func contentHash(_ url: URL) throws -> String {
        
        let accessing = url.startAccessingSecurityScopedResource()
        
        defer {
            
            if accessing {
                
                url.stopAccessingSecurityScopedResource()
            
            }
        
        }
        
        return try coordinatedRead(url) {
            
            source in
            
            let handle = try FileHandle(forReadingFrom: source)
            
            defer {
                
                try? handle.close()
            
            }
            
            var hash = SHA256()
            
            while let data = try handle.read( upToCount: 1_048_576), !data.isEmpty {
                
                hash.update( data: data)
            
            }
            
            return hash.finalize().map {
                String(format: "%02x", $0)
            }.joined()
            
        }
        
    }

    static func isPresent(_ url: URL) throws -> Bool {
        
        
        do {
            
            _ = try url.resourceValues( forKeys: [.isDirectoryKey] );
            
            return true
        
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            
            guard ["json", "pdf"].contains(url.pathExtension.lowercased()) else {
                return false
            }
            
            let placeholder = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).icloud")
            
            do {
                
                _ = try placeholder.resourceValues(forKeys: [.isDirectoryKey]);
                
                return true
            
            }catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                return false
            }
            
        }
        
    }

    static func coordinatedRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        
        var coordinationError: NSError?
        
        var result: Result<T, Error>?
        
        NSFileCoordinator().coordinate( readingItemAt: url, options: [], error: &coordinationError) {
            
            coordinatedURL in
            
            result = Result {
                try body(coordinatedURL)
            }
            
        }
        
        if let coordinationError {
            throw coordinationError
        }
        
        guard let result else {
            throw SyncStoreError.unavailableFile
        }
        
        return try result.get()
        
    }

    static func coordinatedWrite<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        
        var coordinationError: NSError?
        
        var result: Result<T, Error>?
        
        NSFileCoordinator().coordinate(writingItemAt: url, options: .forMerging, error: &coordinationError) {
            coordinatedURL in
            result = Result {
                try body(coordinatedURL)
            }
        }
        
        if let coordinationError {
            throw coordinationError
        }
        
        guard let result else {
            throw SyncStoreError.unavailableFile
        }
        
        return try result.get()
    }
}
