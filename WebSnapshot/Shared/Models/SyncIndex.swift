import Foundation

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
            SyncTagChange(normalizedName: PDFTagName.normalized($0), name: $0, removed: false, stamp: stamp)
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
            
        }
        + previous.filter {
            
            !new.contains(PDFTagName.normalized($0))
        }.map {
        
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

        var result = Self([], max(stamp, other.stamp))

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
            } )
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

        guard
            stamps.allSatisfy({

                $0.counter >= 0 && $0.counter < Int64.max - 1

            })
        else {

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

nonisolated struct SyncLocalPDF: Sendable {
    var id: UUID
    
    var url: URL
    
    var addedAt: Date?
    
    var tagNames: [String]
    
    var sharedHash: String?
    
    var baselineTags: [String]? = nil
}
