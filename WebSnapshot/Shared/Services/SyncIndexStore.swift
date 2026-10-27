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

    func load() throws -> SyncIndex {
        
        var index = SyncIndex()
        
        let indexURL = root.appendingPathComponent("index.json")
        
        if try SyncFileStore.isPresent(indexURL) {
            
            index = try SyncIndex.decode( read(indexURL) )
        
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: indexURL) ?? [] {
        
                index = index.merging( try SyncIndex.decode( read(version.url) ) )
            
            }
        
        }
        
        let changes = root.appendingPathComponent("changes", isDirectory: true)
        
        
        if try SyncFileStore.isPresent(changes) {
            
            let urls = try SyncFileStore.coordinatedRead(changes) {
            
                directory in
                
                try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            
            }
            
            
            let metadata = Set(urls.compactMap(Self.metadataURL)).sorted {
                
                $0.path < $1.path
            
            }
            
            for url in metadata {
                index = index.merging(try SyncIndex.decode( read(url)) )
            }
        
        }
        
        for record in index.files {
        
            if let path = record.location?.relativePath {
                _ = try SyncFileStore(root: root).fileURL(path)
            }
        
        }
        
        return index
    }

    func publish(_ changes: SyncIndex) throws {
        
        guard !changes.files.isEmpty else {
            return
        }
        
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        
        let directory = root.appendingPathComponent("changes", isDirectory: true)
        
        try FileManager.default.createDirectory( at: directory, withIntermediateDirectories: true)
        
        
        let stamps = changes.files.flatMap {
            [$0.location?.stamp, $0.tags?.stamp, $0.deleted]
        }.compactMap {
            $0
        }
        
        
        guard let stamp = stamps.max() else {
            throw SyncStoreError.invalidIndex
        }
        
        
        let url = directory.appendingPathComponent("\(stamp.deviceID.uuidString)-\(stamp.operationID.uuidString).json")
        
        
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
        
        let url = root.appendingPathComponent("index.json")
        
        let data = try index.encoded()
        
        if try SyncFileStore.isPresent(url), try read(url) == data {
            return
        }
        
        try SyncFileStore.coordinatedWrite(url) {
            try data.write( to: $0, options: .atomic)
        }
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
        
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: false)
        
        
        guard !relativePath.hasPrefix("/"), !components.isEmpty, components.allSatisfy({
            
            !$0.isEmpty && $0 != "." && $0 != ".."
            
        }), relativePath.lowercased().hasSuffix(".pdf") else {
        
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
