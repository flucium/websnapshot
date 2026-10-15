import Foundation
import CryptoKit

nonisolated struct SyncStamp: Codable, Equatable, Comparable, Sendable {
    
    var counter: Int64
    
    var deviceID: UUID
    
    var operationID: UUID

    static func < (lhs: Self, rhs: Self) -> Bool {
    
        if lhs.counter != rhs.counter {
            return lhs.counter < rhs.counter
        }
        
        if lhs.deviceID != rhs.deviceID {
            return lhs.deviceID.uuidString < rhs.deviceID.uuidString
        }
        
        return lhs.operationID.uuidString < rhs.operationID.uuidString
    }
}

nonisolated struct SyncPDFLocation: Codable, Equatable, Sendable {
    var relativePath: String
    var contentHash: String
    var addedAt: Date?
    var stamp: SyncStamp
}

nonisolated struct SyncTagChange: Codable, Equatable, Sendable {
    var normalizedName: String
    var name: String
    var removed: Bool
    var stamp: SyncStamp
}

nonisolated struct SyncPDFTags: Codable, Equatable, Sendable {
    var names: [String]
    
    var stamp: SyncStamp
    
    var changes: [SyncTagChange]

    init(_ names: [String], _ stamp: SyncStamp) {
        self.names = names
        
        self.stamp = stamp
        
        changes = names.map {
            SyncTagChange( normalizedName: PDFTagName.normalized($0), name: $0, removed: false, stamp: stamp)
        }
    }

    init(editing names: [String], previous: [String], _ stamp: SyncStamp) {
        self.names = names
        
        self.stamp = stamp
        
        let old = Set(previous.map(PDFTagName.normalized))
        
        let new = Set(names.map(PDFTagName.normalized))
        
        changes = names.filter {
        
            !old.contains(PDFTagName.normalized($0))
        
        }.map {
            
            SyncTagChange(normalizedName: PDFTagName.normalized($0), name: $0, removed: false, stamp: stamp)
        
        } + previous.filter {
            
            !new.contains(PDFTagName.normalized($0)) }.map {
            
                SyncTagChange(normalizedName: PDFTagName.normalized($0), name: $0, removed: true, stamp: stamp)
                
        }
        
    }

    func merging(_ other: Self) -> Self {
        
        var values: [String: SyncTagChange] = [:]
        
        for value in changes + other.changes {
            
            if values[value.normalizedName] == nil || value.stamp > values[value.normalizedName]!.stamp {
                values[value.normalizedName] = value
            }
            
        }
        
        var result = Self( [], max(stamp, other.stamp) )
        
        result.changes = values.values.sorted {
            $0.normalizedName < $1.normalizedName
        }
        
        result.names = result.changes.filter {
            !$0.removed
        }.map(\.name)
        
        return result
    }
}

nonisolated struct SyncPDFRecord: Codable, Equatable, Sendable {
    var id: UUID
    
    var location: SyncPDFLocation?
    
    var tags: SyncPDFTags?
    
    var deleted: SyncStamp?

    var isDeleted: Bool {
        guard let deleted else {
            return false
        }
    
        return location.map {
            deleted >= $0.stamp
        } ?? true
    }

    func merging(_ other: Self) -> Self {
        var result = self
        
        if let value = other.location, result.location == nil || value.stamp > result.location!.stamp {
            result.location = value
        }
        
        if let value = other.tags {
            
            result.tags = result.tags.map {
                $0.merging(value)
            } ?? value
            
        }
        
        if let value = other.deleted, result.deleted == nil || value > result.deleted! {
            result.deleted = value
        }
        
        return result
    }
}

nonisolated struct SyncIndex: Codable, Equatable, Sendable {
    var schemaVersion: Int = 1
    
    var files: [SyncPDFRecord] = []

    var counter: Int64 {
        files.flatMap {
            
            [$0.location?.stamp.counter, $0.tags?.stamp.counter, $0.deleted?.counter]
        
        }
        .compactMap {
            $0
        }.max() ?? 0
    }

    func merging(_ other: Self) -> Self {
        var records: [UUID: SyncPDFRecord] = [:]
        
        for record in files + other.files {
            
            records[record.id] = records[record.id].map {
            
                $0.merging(record)
                
            } ?? record
            
        }
        
        return Self( files: records.values.sorted {
            $0.id.uuidString < $1.id.uuidString
        })
    }

    static func decode(_ data: Data) throws -> Self {
        
        let index = try JSONDecoder().decode(Self.self, from: data)
        
        guard index.schemaVersion == 1 else {
            
            throw SyncStoreError.unsupportedSchema
        
        }
        
        guard Set(index.files.map(\.id)).count == index.files.count else {
            
            throw SyncStoreError.invalidIndex
        
        }
       
        
        let stamps = index.files.flatMap {
           
            record in
            
            [record.location?.stamp, record.tags?.stamp, record.deleted].compactMap {
                $0
            } + (record.tags?.changes.map(\.stamp) ?? [])
        }
        
        guard stamps.allSatisfy({
            
            $0.counter >= 0 && $0.counter < Int64.max - 1
        
        }) else {
            
            throw SyncStoreError.invalidIndex
        
        }
        
        return index
        
    }

    func encoded() throws -> Data {
        
        let encoder = JSONEncoder()
        
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        return try encoder.encode(self)
    
    }

}


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

nonisolated struct SyncLocalPDF: Sendable {
    var id: UUID
    var url: URL
    var addedAt: Date?
    var tagNames: [String]
    var sharedPath: String?
    var sharedHash: String?
    var baselineTags: [String]? = nil
}


nonisolated struct SyncIndexStore: Sendable {
    
    var root: URL

    static var defaultCloudDriveURL: URL {
        let home = FileManager.default.homeDirectory(forUser: NSUserName())
            ?? FileManager.default.homeDirectoryForCurrentUser
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

    func load() throws -> SyncIndex {
        
        var index = SyncIndex()
        
        let indexURL = root.appendingPathComponent("index.json")
        
        if try isPresent(indexURL) {
            
            index = try SyncIndex.decode( read(indexURL) )
        
            for version in NSFileVersion.unresolvedConflictVersionsOfItem(at: indexURL) ?? [] {
        
                index = index.merging( try SyncIndex.decode( read(version.url) ) )
            
            }
        
        }
        
        let changes = root.appendingPathComponent("changes", isDirectory: true)
        
        
        if try isPresent(changes) {
            
            let urls = try coordinatedRead(changes) {
            
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
                _ = try fileURL(path)
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
        
        try coordinatedWrite(url) {
            
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
        
        if try isPresent(url), try read(url) == data {
            return
        }
        
        try coordinatedWrite(url) {
            try data.write( to: $0, options: .atomic)
        }
    }

    func prepareEnable(_ pdfs: [SyncLocalPDF], _ deviceID: UUID,  _ counter: Int64) throws -> SyncIndex {
        
        try FileManager.default.createDirectory( at: root, withIntermediateDirectories: true)
        
        var index = try load()
        
        var next = max(counter, index.counter)
        
        var changes = SyncIndex()
        
        for pdf in pdfs {
            
            let existing = index.files.first {
            
                $0.id == pdf.id
            
            }
            
            if existing?.isDeleted == true {
                
                continue
            
            }
            
            let hash = try Self.contentHash(pdf.url)
            
            guard next < Int64.max - 1 else {
                
                throw SyncStoreError.invalidIndex
            
            }
            
            next += 1
            
            let stamp = SyncStamp( counter: next, deviceID: deviceID, operationID: UUID() )
            
            
            var location: SyncPDFLocation
            
            if let current = existing?.location, current.contentHash == hash || pdf.sharedHash == hash {
            
                location = current
                
                if current.contentHash == hash {
                    try Self.copy(pdf.url, to: fileURL(current.relativePath), expectedHash: hash)
                }
                
            } else {
                
                let path = "PDFs/\(pdf.id.uuidString)/\(hash)/\(pdf.url.lastPathComponent)"
                
                let destination = try fileURL(path)
                
                try Self.copy(pdf.url, to: destination, expectedHash: hash)
                
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
            
            changes.files.append(record)
            
            index = index.merging( SyncIndex( files: [record] ) )
            
        }
        
        
        try publish(changes)
        
        try writeSnapshot(index)
        
        return index
    }

    func prepareDisable(_ pending: SyncIndex, _ localRoot: URL) throws -> (SyncIndex, [UUID: URL]) {
        
        try publish(pending)
        
        var index = try load().merging(pending)
        
        var destinations: [UUID: URL] = [:]

        var usedDestinations: Set<URL> = []
        
        for (offset, record) in index.files.enumerated() where !record.isDeleted {
        
            guard var location = record.location else {
                throw SyncStoreError.invalidIndex
            }
            
            let source = try fileURL(location.relativePath)
            
            location.contentHash = try Self.contentHash(source)
            
            index.files[offset].location = location
            
            var destination = localRoot.appendingPathComponent(source.lastPathComponent)
            
            var suffix = 2
            
            while try isPresent(destination) {
                let canonical = destination.resolvingSymlinksInPath().standardizedFileURL

                let values = try destination.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])

                if !usedDestinations.contains(canonical), values.isRegularFile == true, values.isSymbolicLink != true,
                   try Self.contentHash(destination) == location.contentHash {
                    break
                }

                destination = localRoot.appendingPathComponent(URL.pdfFileName(source.lastPathComponent, nil, " \(suffix)"))
                suffix += 1
            }
            
            try Self.copy(source, to: destination, expectedHash: location.contentHash)
            
            destinations[record.id] = destination

            usedDestinations.insert(destination.resolvingSymlinksInPath().standardizedFileURL)
            
        }
        
        return (index, destinations)
        
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

    private func isPresent(_ url: URL) throws -> Bool {
        
        
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
        try coordinatedRead(url) {
            try Data( contentsOf: $0)
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

    private func coordinatedRead<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        try Self.coordinatedRead(url, body)
    }

    private func coordinatedWrite<T>(_ url: URL, _ body: (URL) throws -> T) throws -> T {
        try Self.coordinatedWrite(url, body)
    }
}
