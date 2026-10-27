import Foundation
import XCTest
@testable import WebSnapshot

nonisolated final class SyncIndexStoreTests: XCTestCase {
    func testConcurrentTagAdditionsAndRemovalMergeWithoutLosingOtherTags() throws {
        let id = UUID()
        let baseline = record(id, tags: ["Keep", "Remove"], counter: 1)
        let first = SyncPDFRecord(id: id, location: nil,
                                 tags: SyncPDFTags(editing: ["Keep", "A"], previous: ["Keep", "Remove"], stamp(2)), deleted: nil)
        let second = SyncPDFRecord(id: id, location: nil,
                                  tags: SyncPDFTags(editing: ["Keep", "Remove", "B"], previous: ["Keep", "Remove"], stamp(2)), deleted: nil)
        let left = SyncIndex(files: [baseline]).merging(SyncIndex(files: [first])).merging(SyncIndex(files: [second]))
        let right = SyncIndex(files: [second]).merging(SyncIndex(files: [baseline])).merging(SyncIndex(files: [first]))
        XCTAssertEqual(left, right)
        XCTAssertEqual(Set(try XCTUnwrap(left.files.first?.tags).names), ["Keep", "A", "B"])
        XCTAssertEqual(left.files.first?.location, baseline.location)
    }

    func testDeletionSurvivesDelayedMetadataAndTagUpdates() {
        let id = UUID()
        let original = record(id, tags: ["Original"], counter: 1)
        let deleted = SyncPDFRecord(id: id, location: nil, tags: nil, deleted: stamp(3))
        let edit = SyncPDFRecord(id: id, location: nil, tags: SyncPDFTags(["Late"], stamp(4)), deleted: nil)
        let index = SyncIndex(files: [deleted]).merging(SyncIndex(files: [original, edit]))
        XCTAssertTrue(index.files[0].isDeleted)
        XCTAssertEqual(index.merging(index), index)
    }

    func testImmutableChangesRecoverBothDevicesAfterSnapshotOverwrite() throws {
        try withDirectory { directory in
            let store = SyncIndexStore(root: directory)
            let first = SyncIndex(files: [record(UUID(), counter: 1)])
            let second = SyncIndex(files: [record(UUID(), counter: 1)])
            try store.publish(first)
            try store.publish(second)
            try store.writeSnapshot(second)
            let loaded = try store.load()
            XCTAssertEqual(Set(loaded.files.map(\.id)), Set((first.files + second.files).map(\.id)))
            try store.publish(first)
            XCTAssertEqual(try store.load(), loaded)
        }
    }

    func testEnableCopiesOriginalsAndWritesPortableIndex() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            try Data("fixture".utf8).write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let added = Date(timeIntervalSince1970: 123)
            let id = UUID()
            let local = SyncLocalPDF(id: id, url: source, addedAt: added, tagNames: ["Article"], sharedHash: nil)
            let index = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 0)
            let entry = try XCTUnwrap(index.files.first)
            let location = try XCTUnwrap(entry.location)
            XCTAssertEqual(entry.id, id)
            XCTAssertEqual(location.addedAt, added)
            XCTAssertEqual(entry.tags?.names, ["Article"])
            XCTAssertFalse(location.relativePath.hasPrefix("/"))
            XCTAssertEqual(try Data(contentsOf: source), Data("fixture".utf8))
            XCTAssertEqual(try Data(contentsOf: SyncFileStore(root: store.root).fileURL(location.relativePath)), Data("fixture".utf8))
            XCTAssertEqual(try store.load(), index)
            XCTAssertEqual(try SyncIndex.decode(Data(contentsOf: store.root.appendingPathComponent("index.json"))), index)
        }
    }

    func testReenableRetainsRemoteTagsWhenLocalCopyWasNotEdited() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("xyz.pdf")
            try Data("fixture".utf8).write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let id = UUID()
            var local = SyncLocalPDF(id: id, url: source, addedAt: nil, tagNames: ["Original"], sharedHash: nil)
            let initial = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 0)
            local.sharedHash = initial.files.first?.location?.contentHash
            local.baselineTags = ["Original"]
            let remote = SyncPDFRecord(id: id, location: nil,
                                       tags: SyncPDFTags(editing: ["Original", "Remote"], previous: ["Original"], stamp(10)), deleted: nil)
            try store.publish(SyncIndex(files: [remote]))
            let index = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 1)
            XCTAssertEqual(Set(index.files[0].tags?.names ?? []), ["Original", "Remote"])
            XCTAssertEqual(index.files[0].location?.relativePath, initial.files[0].location?.relativePath)
        }
    }

    func testReenableMergesOfflineTagEditsWithRemoteEdits() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("xyz.pdf")
            try Data("fixture".utf8).write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let id = UUID()
            var local = SyncLocalPDF(id: id, url: source, addedAt: nil, tagNames: ["Original"], sharedHash: nil)
            _ = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 0)
            local.baselineTags = ["Original"]
            local.tagNames = ["Original", "Offline"]
            let remote = SyncPDFRecord(id: id, location: nil,
                                       tags: SyncPDFTags(editing: ["Original", "Remote"], previous: ["Original"], stamp(10)), deleted: nil)
            try store.publish(SyncIndex(files: [remote]))
            let index = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 1)
            XCTAssertEqual(Set(index.files[0].tags?.names ?? []), ["Original", "Remote", "Offline"])
        }
    }

    func testDisableCopiesPDFsWithoutDeletingCloudFiles() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            try Data("fixture".utf8).write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let id = UUID()
            _ = try SyncMigration(root: store.root).prepareEnable([SyncLocalPDF(id: id, url: source, addedAt: nil, tagNames: [], sharedHash: nil)], UUID(), 0)
            let (index, urls) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory.appendingPathComponent("local"))
            let local = try XCTUnwrap(urls[id])
            let cloud = try SyncFileStore(root: store.root).fileURL(XCTUnwrap(index.files[0].location).relativePath)
            XCTAssertNotEqual(local, cloud)
            XCTAssertEqual(try Data(contentsOf: local), try Data(contentsOf: cloud))
            XCTAssertTrue(FileManager.default.fileExists(atPath: cloud.path))
        }
    }

    func testDisableFailsForUndownloadedPDFRatherThanDroppingItsEntry() throws {
        try withDirectory { directory in
            let store = SyncIndexStore(root: directory)
            let index = SyncIndex(files: [record(UUID(), counter: 1)])
            try store.publish(index)
            try store.writeSnapshot(index)
            XCTAssertThrowsError(try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory.appendingPathComponent("local")))
            XCTAssertEqual(try store.load(), index)
        }
    }

    func testDisableRejectsActiveRecordWithoutLocation() throws {
        try withDirectory { directory in
            let store = SyncIndexStore(root: directory)
            let incomplete = SyncPDFRecord(id: UUID(), location: nil, tags: SyncPDFTags(["Keep"], stamp(2)), deleted: nil)
            let index = SyncIndex(files: [incomplete])
            try store.publish(index)
            let destination = directory.appendingPathComponent("local")

            XCTAssertThrowsError(try SyncMigration(root: store.root).prepareDisable(SyncIndex(), destination)) {
                XCTAssertEqual($0 as? SyncStoreError, .invalidIndex)
            }

            XCTAssertEqual(try store.load(), index)
            XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        }
    }

    func testDisableAcceptsDeletedRecordWithoutLocation() throws {
        try withDirectory { directory in
            let store = SyncIndexStore(root: directory)
            let deleted = SyncPDFRecord(id: UUID(), location: nil, tags: nil, deleted: stamp(2))
            let index = SyncIndex(files: [deleted])
            try store.publish(index)

            let (copied, urls) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory.appendingPathComponent("local"))

            XCTAssertEqual(copied, index)
            XCTAssertTrue(urls.isEmpty)
            XCTAssertEqual(try store.load(), index)
        }
    }

    func testDisableCopiesIntoSelectedFolderWithoutOverwritingSameNames() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            let contents = Data("fixture".utf8)
            try contents.write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let pdfs = (0..<2).map { _ in
                SyncLocalPDF(id: UUID(), url: source, addedAt: nil, tagNames: [], sharedHash: nil)
            }
            _ = try SyncMigration(root: store.root).prepareEnable(pdfs, UUID(), 0)
            let destination = directory.appendingPathComponent("local", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let existing = destination.appendingPathComponent("abcd.pdf")
            let original = Data("existing PDF".utf8)
            try original.write(to: existing)

            let (_, urls) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), destination)

            XCTAssertEqual(Set(urls.values.map(\.lastPathComponent)), ["abcd 2.pdf", "abcd 3.pdf"])
            for url in urls.values {
                XCTAssertEqual(url.deletingLastPathComponent(), destination)
                XCTAssertEqual(try Data(contentsOf: url), contents)
            }
            XCTAssertEqual(try Data(contentsOf: existing), original)

            let (_, repeatedURLs) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), destination)
            XCTAssertEqual(repeatedURLs, urls)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(), ["abcd 2.pdf", "abcd 3.pdf", "abcd.pdf"])
        }
    }

    func testDisableReusesUnchangedOriginalInDestination() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            let contents = Data("fixture".utf8)
            try contents.write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let pdf = SyncLocalPDF(id: UUID(), url: source, addedAt: nil, tagNames: ["Keep"], sharedHash: nil)
            _ = try SyncMigration(root: store.root).prepareEnable([pdf], UUID(), 0)

            let (index, urls) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory)

            XCTAssertEqual(urls[pdf.id], source)
            XCTAssertEqual(index.files.first?.tags?.names, ["Keep"])
            XCTAssertEqual(try Data(contentsOf: source), contents)
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("abcd 2.pdf").path))
            let cloud = try SyncFileStore(root: store.root).fileURL(XCTUnwrap(index.files.first?.location).relativePath)
            XCTAssertEqual(try Data(contentsOf: cloud), contents)
        }
    }

    func testDisablePreservesDifferentContentAndReusesPreviousCopy() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            try Data("synced PDF".utf8).write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let pdf = SyncLocalPDF(id: UUID(), url: source, addedAt: nil, tagNames: [], sharedHash: nil)
            _ = try SyncMigration(root: store.root).prepareEnable([pdf], UUID(), 0)
            try Data("local edit".utf8).write(to: source)

            let (_, firstURLs) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory)
            let (_, secondURLs) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory)

            XCTAssertEqual(firstURLs[pdf.id], directory.appendingPathComponent("abcd 2.pdf"))
            XCTAssertEqual(secondURLs, firstURLs)
            XCTAssertEqual(try Data(contentsOf: source), Data("local edit".utf8))
            XCTAssertEqual(try Data(contentsOf: XCTUnwrap(secondURLs[pdf.id])), Data("synced PDF".utf8))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("abcd 3.pdf").path))
        }
    }

    func testRetryAfterPartialDisableDoesNotDuplicateCompletedCopies() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            let contents = Data("fixture".utf8)
            try contents.write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let pdfs = (1...2).map {
                SyncLocalPDF(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000\($0)")!, url: source, addedAt: nil, tagNames: [], sharedHash: nil)
            }
            let index = try SyncMigration(root: store.root).prepareEnable(pdfs, UUID(), 0)
            let missing = try SyncFileStore(root: store.root).fileURL(XCTUnwrap(index.files.last?.location).relativePath)
            try FileManager.default.removeItem(at: missing)
            let destination = directory.appendingPathComponent("local", isDirectory: true)

            XCTAssertThrowsError(try SyncMigration(root: store.root).prepareDisable(SyncIndex(), destination))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path), ["abcd.pdf"])
            try contents.write(to: missing)

            let (_, urls) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), destination)

            XCTAssertEqual(urls[pdfs[0].id], destination.appendingPathComponent("abcd.pdf"))
            XCTAssertEqual(urls[pdfs[1].id], destination.appendingPathComponent("abcd 2.pdf"))
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destination.path).sorted(), ["abcd 2.pdf", "abcd.pdf"])
        }
    }

    func testReenableRestoresMissingCloudPDFWithUnchangedLocalCopy() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            let contents = Data("fixture".utf8)
            try contents.write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            var local = SyncLocalPDF(id: UUID(), url: source, addedAt: nil, tagNames: [], sharedHash: nil)
            let initial = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 0)
            let location = try XCTUnwrap(initial.files.first?.location)
            let cloudPDF = try SyncFileStore(root: store.root).fileURL(location.relativePath)
            local.sharedHash = location.contentHash
            try FileManager.default.removeItem(at: cloudPDF)

            let restored = try SyncMigration(root: store.root).prepareEnable([local], UUID(), initial.counter)

            XCTAssertEqual(restored.files.first?.location, location)
            XCTAssertEqual(try Data(contentsOf: cloudPDF), contents)
        }
    }

    func testReenablePreservesRemoteContentWhenLocalCopyIsUnchanged() throws {
        try withDirectory { directory in
            let source = directory.appendingPathComponent("abcd.pdf")
            try Data("original".utf8).write(to: source)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            var local = SyncLocalPDF(id: UUID(), url: source, addedAt: nil, tagNames: [], sharedHash: nil)
            let initial = try SyncMigration(root: store.root).prepareEnable([local], UUID(), 0)
            local.sharedHash = initial.files.first?.location?.contentHash
            let remote = directory.appendingPathComponent("remote.pdf")
            try Data("remote edit".utf8).write(to: remote)
            let changed = SyncLocalPDF(id: local.id, url: remote, addedAt: nil, tagNames: [], sharedHash: nil)
            let updated = try SyncMigration(root: store.root).prepareEnable([changed], UUID(), initial.counter)

            let restored = try SyncMigration(root: store.root).prepareEnable([local], UUID(), initial.counter)

            let location = try XCTUnwrap(restored.files.first?.location)
            XCTAssertEqual(location, updated.files.first?.location)
            XCTAssertEqual(try Data(contentsOf: SyncFileStore(root: store.root).fileURL(location.relativePath)), Data("remote edit".utf8))
        }
    }

    func testMalformedIndexIsPreserved() throws {
        try withDirectory { directory in
            let url = directory.appendingPathComponent("index.json")
            let malformed = Data("{broken".utf8)
            try malformed.write(to: url)
            XCTAssertThrowsError(try SyncMigration(root: directory).prepareEnable([], UUID(), 0))
            XCTAssertEqual(try Data(contentsOf: url), malformed)
        }
    }

    func testUnsupportedSchemaIsRejected() {
        XCTAssertThrowsError(try SyncIndex.decode(Data("{\"schemaVersion\":2,\"files\":[]}".utf8)))
    }

    func testUndownloadedIndexCannotBeOverwrittenByAnEmptySnapshot() throws {
        try withDirectory { directory in
            let placeholder = directory.appendingPathComponent(".index.json.icloud")
            let contents = Data("placeholder".utf8)
            try contents.write(to: placeholder)
            let store = SyncIndexStore(root: directory)
            // A plain temporary directory cannot materialize an iCloud item.
            // It must fail safely instead of creating a replacement index.
            XCTAssertThrowsError(try SyncMigration(root: store.root).prepareEnable([], UUID(), 0))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
            XCTAssertEqual(try Data(contentsOf: placeholder), contents)
        }
    }

    func testUndownloadedChangeCannotBeIgnored() throws {
        try withDirectory { directory in
            let changes = directory.appendingPathComponent("changes", isDirectory: true)
            try FileManager.default.createDirectory(at: changes, withIntermediateDirectories: true)
            try Data("placeholder".utf8).write(to: changes.appendingPathComponent(".operation.json.icloud"))
            XCTAssertThrowsError(try SyncIndexStore(root: directory).load())
        }
    }

    func testPathsCannotEscapeLibraryIncludingThroughSymlinks() throws {
        try withDirectory { directory in
            let root = directory.appendingPathComponent("websnapshot")
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            let store = SyncIndexStore(root: root)
            for path in ["../outside.pdf", "/tmp/outside.pdf", "PDFs/../../outside.pdf", "PDFs//file.pdf", "index.json"] {
                XCTAssertThrowsError(try SyncFileStore(root: store.root).fileURL(path))
            }
            try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("link"), withDestinationURL: directory)
            XCTAssertThrowsError(try SyncFileStore(root: store.root).fileURL("link/outside.pdf"))
        }
    }

    func testFolderMustBeLowercaseAndDirectlyInICloudDrive() throws {
        let drive = URL(fileURLWithPath: "/private/tmp/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        let expected = drive.appendingPathComponent("websnapshot", isDirectory: true)
        XCTAssertEqual(try SyncFileStore.cloudFolder(drive), expected)
        XCTAssertEqual(try SyncFileStore.cloudFolder(expected), expected)
        XCTAssertThrowsError(try SyncFileStore.cloudFolder(drive.appendingPathComponent("WebSnapshot")))
        XCTAssertThrowsError(try SyncFileStore.cloudFolder(drive.appendingPathComponent("Other/websnapshot")))
        XCTAssertThrowsError(try SyncFileStore.cloudFolder(URL(fileURLWithPath: "/tmp/websnapshot")))
    }

    func testExistingFolderIsNormalizedToLowercaseWithoutLosingFiles() throws {
        try withDirectory { directory in
            let drive = directory.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            let uppercase = drive.appendingPathComponent("WebSnapshot", isDirectory: true)
            try FileManager.default.createDirectory(at: uppercase, withIntermediateDirectories: true)
            try Data("fixture".utf8).write(to: uppercase.appendingPathComponent("abcd.pdf"))
            let folder = try SyncFileStore.prepareCloudFolder(drive)
            XCTAssertEqual(folder.lastPathComponent, "websnapshot")
            let names = try FileManager.default.contentsOfDirectory(atPath: drive.path)
            XCTAssertTrue(names.contains("websnapshot"))
            XCTAssertFalse(names.contains("WebSnapshot"))
            XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("abcd.pdf")), Data("fixture".utf8))
        }
    }

    func testDrivePermissionMustReferToRootInsteadOfLibraryFolder() throws {
        let drive = URL(fileURLWithPath: "/private/tmp/Mobile Documents/com~apple~CloudDocs", isDirectory: true)
        XCTAssertEqual(try SyncFileStore.cloudDrive(drive), drive)
        XCTAssertThrowsError(try SyncFileStore.cloudDrive(drive.appendingPathComponent("websnapshot")))
        XCTAssertThrowsError(try SyncFileStore.cloudDrive(drive.appendingPathComponent("Other")))
        XCTAssertThrowsError(try SyncFileStore.cloudDrive(URL(fileURLWithPath: "/tmp")))
    }

    func testReenableRecreatesRemovedLibraryFromDriveBookmarkAndLocalCopy() throws {
        try withDirectory { directory in
            let drive = directory.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
            let bookmark = try drive.bookmarkData(options: [.withSecurityScope])
            let cloud = try SyncFileStore.prepareCloudFolder(drive)
            let source = directory.appendingPathComponent("abcd.pdf")
            try Data("fixture".utf8).write(to: source)
            let id = UUID()
            let pdf = SyncLocalPDF(id: id, url: source, addedAt: nil, tagNames: ["Keep"], sharedHash: nil)
            let store = SyncIndexStore(root: cloud)
            _ = try SyncMigration(root: store.root).prepareEnable([pdf], UUID(), 0)
            let (index, local) = try SyncMigration(root: store.root).prepareDisable(SyncIndex(), directory.appendingPathComponent("local"))
            try FileManager.default.removeItem(at: cloud)

            var stale = false
            let remembered = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                     bookmarkDataIsStale: &stale)
            let accessing = remembered.startAccessingSecurityScopedResource()
            defer { if accessing { remembered.stopAccessingSecurityScopedResource() } }
            let recreated = try SyncFileStore.prepareCloudFolder(SyncFileStore.cloudDrive(remembered))
            let localPDF = SyncLocalPDF(id: id, url: try XCTUnwrap(local[id]), addedAt: nil, tagNames: ["Keep"],
                                       sharedHash: index.files.first?.location?.contentHash,
                                       baselineTags: ["Keep"])
            let restored = try SyncMigration(root: recreated).prepareEnable([localPDF], UUID(), index.counter)

            XCTAssertEqual(recreated.resolvingSymlinksInPath(), cloud.resolvingSymlinksInPath())
            XCTAssertEqual(restored.files.first?.id, id)
            XCTAssertEqual(restored.files.first?.tags?.names, ["Keep"])
            let path = try XCTUnwrap(restored.files.first?.location?.relativePath)
            XCTAssertEqual(try Data(contentsOf: SyncFileStore(root: recreated).fileURL(path)), Data("fixture".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: recreated.appendingPathComponent("index.json").path))
        }
    }

    func testDriveBookmarkRecreatesOriginalFolderAfterLibraryMoves() throws {
        try withDirectory { directory in
            let drive = directory.appendingPathComponent("Mobile Documents/com~apple~CloudDocs", isDirectory: true)
            try FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
            let bookmark = try drive.bookmarkData(options: [.withSecurityScope])
            let cloud = try SyncFileStore.prepareCloudFolder(drive)
            let contents = Data("fixture".utf8)
            try contents.write(to: cloud.appendingPathComponent("abcd.pdf"))
            let moved = directory.appendingPathComponent("moved/websnapshot")
            try FileManager.default.createDirectory(at: moved.deletingLastPathComponent(), withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: cloud, to: moved)

            var stale = false
            let remembered = try URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope, .withoutUI],
                                     bookmarkDataIsStale: &stale)
            let accessing = remembered.startAccessingSecurityScopedResource()
            defer { if accessing { remembered.stopAccessingSecurityScopedResource() } }
            let recreated = try SyncFileStore.prepareCloudFolder(SyncFileStore.cloudDrive(remembered))

            XCTAssertEqual(recreated.resolvingSymlinksInPath(), cloud.resolvingSymlinksInPath())
            XCTAssertTrue(FileManager.default.fileExists(atPath: recreated.path))
            XCTAssertEqual(try Data(contentsOf: moved.appendingPathComponent("abcd.pdf")), contents)
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: recreated.path).isEmpty)
        }
    }

    func testSameFilenameOnTwoDevicesDoesNotOverwriteEitherPDF() throws {
        try withDirectory { directory in
            let a = directory.appendingPathComponent("a/abcd.pdf")
            let b = directory.appendingPathComponent("b/abcd.pdf")
            for url in [a, b] { try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true) }
            try Data("first".utf8).write(to: a)
            try Data("second".utf8).write(to: b)
            let store = SyncIndexStore(root: directory.appendingPathComponent("websnapshot"))
            let first = SyncLocalPDF(id: UUID(), url: a, addedAt: nil, tagNames: [], sharedHash: nil)
            let second = SyncLocalPDF(id: UUID(), url: b, addedAt: nil, tagNames: [], sharedHash: nil)
            _ = try SyncMigration(root: store.root).prepareEnable([first], UUID(), 0)
            let index = try SyncMigration(root: store.root).prepareEnable([second], UUID(), 0)
            let firstPath = try XCTUnwrap(index.files.first { $0.id == first.id }?.location?.relativePath)
            let secondPath = try XCTUnwrap(index.files.first { $0.id == second.id }?.location?.relativePath)
            XCTAssertNotEqual(firstPath, secondPath)
            XCTAssertEqual(try Data(contentsOf: SyncFileStore(root: store.root).fileURL(firstPath)), Data("first".utf8))
            XCTAssertEqual(try Data(contentsOf: SyncFileStore(root: store.root).fileURL(secondPath)), Data("second".utf8))
        }
    }

    private func record(_ id: UUID, tags: [String] = [], counter: Int64) -> SyncPDFRecord {
        let stamp = stamp(counter)
        return SyncPDFRecord(id: id,
                             location: SyncPDFLocation(relativePath: "PDFs/\(id.uuidString)/abcd.pdf", contentHash: "fixture", addedAt: nil, stamp: stamp),
                             tags: SyncPDFTags(tags, stamp), deleted: nil)
    }

    private func stamp(_ counter: Int64) -> SyncStamp {
        SyncStamp(counter: counter, deviceID: UUID(), operationID: UUID())
    }

    private func withDirectory(_ body: (URL) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(directory)
    }

    static let standaloneTests = [
        ("concurrent tag changes", testConcurrentTagAdditionsAndRemovalMergeWithoutLosingOtherTags),
        ("deletion tombstones", testDeletionSurvivesDelayedMetadataAndTagUpdates),
        ("overwritten snapshot recovery", testImmutableChangesRecoverBothDevicesAfterSnapshotOverwrite),
        ("enable migration", testEnableCopiesOriginalsAndWritesPortableIndex),
        ("reenable remote tags", testReenableRetainsRemoteTagsWhenLocalCopyWasNotEdited),
        ("reenable offline edits", testReenableMergesOfflineTagEditsWithRemoteEdits),
        ("disable migration", testDisableCopiesPDFsWithoutDeletingCloudFiles),
        ("incomplete active record", testDisableRejectsActiveRecordWithoutLocation),
        ("deleted record without location", testDisableAcceptsDeletedRecordWithoutLocation),
        ("disable destination and collisions", testDisableCopiesIntoSelectedFolderWithoutOverwritingSameNames),
        ("reuse original PDF", testDisableReusesUnchangedOriginalInDestination),
        ("reuse previous copy and preserve edits", testDisablePreservesDifferentContentAndReusesPreviousCopy),
        ("retry partial copy", testRetryAfterPartialDisableDoesNotDuplicateCompletedCopies),
        ("restore missing cloud PDF", testReenableRestoresMissingCloudPDFWithUnchangedLocalCopy),
        ("preserve remote PDF changes", testReenablePreservesRemoteContentWhenLocalCopyIsUnchanged),
        ("undownloaded PDF", testDisableFailsForUndownloadedPDFRatherThanDroppingItsEntry),
        ("malformed index", testMalformedIndexIsPreserved),
        ("schema version", testUnsupportedSchemaIsRejected),
        ("undownloaded index", testUndownloadedIndexCannotBeOverwrittenByAnEmptySnapshot),
        ("undownloaded history", testUndownloadedChangeCannotBeIgnored),
        ("path containment", testPathsCannotEscapeLibraryIncludingThroughSymlinks),
        ("fixed lowercase folder", testFolderMustBeLowercaseAndDirectlyInICloudDrive),
        ("normalize existing folder", testExistingFolderIsNormalizedToLowercaseWithoutLosingFiles),
        ("permission to drive root", testDrivePermissionMustReferToRootInsteadOfLibraryFolder),
        ("recreate removed library", testReenableRecreatesRemovedLibraryFromDriveBookmarkAndLocalCopy),
        ("recreate moved library", testDriveBookmarkRecreatesOriginalFolderAfterLibraryMoves),
        ("duplicate PDF filenames", testSameFilenameOnTwoDevicesDoesNotOverwriteEitherPDF),
    ]
}
