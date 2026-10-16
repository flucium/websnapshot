import Foundation
import SwiftData
import CoreGraphics
import PDFKit

@MainActor
final class LibraryService {
    static func importPDF(_ sourceURL: URL, _  directoryURL: URL, _ modelContext: ModelContext) throws -> URL {

        try LibrarySyncService.shared.requireReady()

        let isAccessingSource = sourceURL.startAccessingSecurityScopedResource()

        let isAccessingDirectory = directoryURL.startAccessingSecurityScopedResource()

        defer {
            if isAccessingSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }

            if isAccessingDirectory {
                directoryURL.stopAccessingSecurityScopedResource()
            }
        }

        guard sourceURL.pathExtension.lowercased() == "pdf", let document = PDFDocument(url: sourceURL), document.pageCount > 0 || document.isLocked else {

            throw AppError.invalidFileType("Choose a valid PDF file to import.")

        }

        if LibrarySyncService.isEnabled(modelContext) {

            let data = try SyncIndexStore.coordinatedRead(sourceURL) {
                try Data(contentsOf: $0)
            }

            return try LibrarySyncService.shared.savePDF( data, sourceURL.lastPathComponent, modelContext )
        }

        if sourceURL.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL == directoryURL.resolvingSymlinksInPath().standardizedFileURL {

            try PDFFileService.save(modelContext, sourceURL)

            return sourceURL
        }

        let destination = availablePDFURL(directoryURL, sourceURL.lastPathComponent)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination)

            do {

                try PDFFileService.save(modelContext, destination)

            } catch {

                do {

                    try FileManager.default.removeItem(at: destination)

                } catch let cleanupError {

                    AppLogger.record(AppError(cleanupError), "Remove PDF after failed import", destination)

                }

                throw error

            }

            return destination

        } catch {
            throw AppError(error)
        }
    }

    static func exportPDF(_ sourceURL: URL, _ destinationURL: URL) throws {

        guard sourceURL.resolvingSymlinksInPath().standardizedFileURL != destinationURL.resolvingSymlinksInPath().standardizedFileURL else {
            throw AppError.error("Choose a different location for the exported PDF.")
        }

        let isAccessingSource = sourceURL.startAccessingSecurityScopedResource()

        let isAccessingDestination = destinationURL.startAccessingSecurityScopedResource()

        defer {

            if isAccessingSource {
                sourceURL.stopAccessingSecurityScopedResource()
            }

            if isAccessingDestination {
                destinationURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)

            try data.write(to: destinationURL, options: .atomic)

        } catch {
            throw AppError(error)
        }
    }

    static func delete( _ modelContext: ModelContext, _ url: URL, _ resolvedURL: URL, _ removeFile: ((URL) throws -> Void)? = nil ) throws {
        try LibrarySyncService.shared.requireReady()

        if LibrarySyncService.isEnabled(modelContext) {

            try PDFFileService.delete(modelContext, url)

            return

        }

        if let removeFile {

            try removeFile(resolvedURL)

        } else {

            try FileIO.delete(resolvedURL)

        }

        do {

            try PDFFileService.delete(modelContext, url)

        } catch {
            AppLogger.recordDiagnostic("The file was deleted, but its library entry could not be removed. Automatic synchronization will retry the cleanup.","Delete PDF library entry",resolvedURL)

            throw error
        }
    }

    static func deleteMissingFiles(_ modelContext: ModelContext,_ pdfFiles: [PDFFile],_ confirmedDeletedFileIDs: Set<PersistentIdentifier> = []) throws {

        if LibrarySyncService.shared.state.isSwitching || LibrarySyncService.isEnabled(modelContext) {
            return
        }

        var needsSave = false

        let missingPDFFiles = pdfFiles.filter {
            $0.availability == .missing || (confirmedDeletedFileIDs.contains($0.persistentModelID) && FileIO.exists($0.resolvedURL) == false)
        }

        PDFTagService.deleteTagsOrphanedByDeleting(missingPDFFiles, modelContext )

        for pdfFile in missingPDFFiles {

            modelContext.delete(pdfFile)

            needsSave = true

        }

        if needsSave {
            do {
                try modelContext.save()
            } catch {

                modelContext.rollback()

                throw AppError.system( "The library could not be synchronized.", error.localizedDescription, error )
            }
        }
    }

    static func matches(_ pdfFile: PDFFile, _ searchText: String, _ mode: LibrarySearchMode ) -> Bool {

        let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.isEmpty == false else {
            return true
        }

        let titleMatches = pdfFile.resolvedURL.lastPathComponent.localizedCaseInsensitiveContains(searchText)

        let tagMatches = pdfFile.tags.contains {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        var contentMatches: Bool {
            pdfFile.searchableText?.localizedCaseInsensitiveContains(searchText) ?? false
        }

        return switch mode {
        case .all:
            titleMatches || tagMatches || contentMatches
        case .title:
            titleMatches
        case .tag:
            tagMatches
        }
    }

    nonisolated static func textForTranslation(_ url: URL,_ pageIndex: Int ) async throws -> String {
        let isAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data

        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppError(error)
        }

        guard
            let document = PDFDocument(data: data), let page = document.page(at: pageIndex)
        else {
            throw AppError.notFound("The displayed PDF page was not found.")
        }

        let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? String()

        if embeddedText.isEmpty == false {
            return embeddedText
        }

        let image = try render(page, 300)

        let recognizedText = try await OCR.recognizeText(image).trimmingCharacters(in: .whitespacesAndNewlines)

        guard recognizedText.isEmpty == false else {
            throw AppError.textRecognitionFailed("No text was found on the displayed PDF page.")
        }

        return recognizedText
    }

    nonisolated static func render(_ page: PDFPage, _ dpi: CGFloat) throws -> CGImage {
        try PDFContentService.render(page, dpi)
    }
}
