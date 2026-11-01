import Foundation
import XCTest

@testable import WebSnapshot

@MainActor
final class PDFFileStoreTests: XCTestCase {
    private enum Failure: Error { case registration }

    func testImportCreatesMissingDestinationAndPreservesSource() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Missing/Imported", isDirectory: true)
        let source = directory.appendingPathComponent("Source.pdf")
        let data = Data("original".utf8)
        try data.write(to: source)
        var registered: URL?

        let imported = try PDFFileStore.copy(source, to: destination) {
            registered = $0
        }

        XCTAssertEqual(registered, imported)
        XCTAssertEqual(imported.deletingLastPathComponent(), destination)
        XCTAssertEqual(try Data(contentsOf: imported), data)
        XCTAssertEqual(try Data(contentsOf: source), data)
    }

    func testFailedRegistrationRemovesOnlyTheNewFile() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appendingPathComponent("Article.pdf")
        let originalData = Data("original".utf8)
        try originalData.write(to: original)

        XCTAssertThrowsError(
            try PDFFileStore.save(Data("new".utf8), "Article.pdf", in: directory) { destination in
                XCTAssertEqual(destination.lastPathComponent, "Article 2.pdf")
                XCTAssertEqual(try Data(contentsOf: destination), Data("new".utf8))
                throw Failure.registration
            })

        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["Article.pdf"])
        XCTAssertEqual(try Data(contentsOf: original), originalData)
    }

    func testFailedRegistrationRestoresOverwrittenContents() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Article.pdf")
        let originalData = Data("original".utf8)
        try originalData.write(to: destination)

        XCTAssertThrowsError(
            try PDFFileStore.write(Data("replacement".utf8), to: destination) { url in
                XCTAssertEqual(try Data(contentsOf: url), Data("replacement".utf8))
                throw Failure.registration
            })

        XCTAssertEqual(try Data(contentsOf: destination), originalData)
    }

    func testFailedImportRegistrationPreservesSourceAndRemovesCopy() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let destination = directory.appendingPathComponent("Imported", isDirectory: true)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("Source.pdf")
        let originalData = Data("original".utf8)
        try originalData.write(to: source)

        XCTAssertThrowsError(
            try PDFFileStore.copy(source, to: destination) { _ in
                throw Failure.registration
            })

        XCTAssertEqual(try Data(contentsOf: source), originalData)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: destination.path).isEmpty)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
