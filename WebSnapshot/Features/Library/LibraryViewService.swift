import Foundation
import SwiftData
import CoreGraphics
import PDFKit
import AppKit
import Translation

@MainActor
final class LibraryViewService {
    static func startTranslation(_ state: LibraryViewState, _ targetLanguage: TranslationLanguage) {
        guard let selectedPDFFile = state.selectedPDFFile else {
            return
        }

        state.appError = nil
        let request = state.beginTranslation(selectedPDFFile, targetLanguage)

        state.translationPreparationTask = Task { @MainActor in
            do {
                try Task.checkCancellation()
                let text = try await textForTranslation(request.url, request.pageIndex)
                try Task.checkCancellation()
                state.prepareTranslation(text, for: request)
            } catch {
                guard state.isCurrentTranslation(request) else { return }
                state.finishTranslation(request)
                if selectedPDFFile.availability == .missing {
                    closeMissingPDF(state)
                }
                handle(error, "Text Could Not Be Prepared", "Prepare PDF text", state, request.url)
            }
        }
    }

    static func translate(
        _ state: LibraryViewState,
        _ session: TranslationSession,
        _ request: LibraryViewState.TranslationRequest
    ) async {
        guard let text = request.text,
              state.isCurrentTranslation(request), !Task.isCancelled else {
            return
        }

        do {
            let translated = try await Translation.translate(session, text)
            try Task.checkCancellation()
            state.completeTranslation(translated, for: request)
        } catch {
            guard state.isCurrentTranslation(request) else { return }
            handle(error, "Translation Could Not Be Completed", "Translate PDF text", state, request.url)
            state.finishTranslation(request)
        }
    }

    static func deletePDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile) {
        do {
            try delete(modelContext, pdfFile.url, pdfFile.resolvedURL)

            state.selectedPDFFile = nil
            state.appError = nil
        } catch {
            handle(error, "PDF Could Not Be Deleted", "Delete PDF", state, pdfFile.resolvedURL)
        }
    }

    static func deleteDisplayedPDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile) {
        let url = pdfFile.url
        let resolvedURL = pdfFile.resolvedURL

        state.cancelTranslation()
        state.selectedPDFFile = nil
        state.appError = nil

        Task { @MainActor in
            await Task.yield()

            do {
                try delete(modelContext, url, resolvedURL)
            } catch {
                handle(error, "PDF Could Not Be Deleted", "Delete PDF", state, resolvedURL)
            }
        }
    }

    static func copyFilePath(_ state: LibraryViewState, _ pdfFile: PDFFile) {
        let resolvedURL = pdfFile.resolvedURL

        do {
            if FileIO.exists(resolvedURL) == false {
                throw AppError.notFound("The PDF file could not be found.")
            }

            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            guard pasteboard.setString(resolvedURL.path, forType: .string) else {
                throw AppError.system("The file path could not be copied.")
            }

            state.appError = nil
        } catch {
            handle(error, "File Path Could Not Be Copied", "Copy PDF path", state, resolvedURL)
        }
    }

    static func synchronizeLibraryFiles(
        _ state: LibraryViewState,
        _ modelContext: ModelContext,
        _ monitor: LibraryPDFFileMonitor,
        _ change: LibraryPDFFileMonitor.Change? = nil
    ) {
        let confirmedDeletedFileIDs: Set<PersistentIdentifier>

        if let change {
            confirmedDeletedFileIDs = change.wasDeleted && FileIO.exists(change.url) == false
                ? [change.fileID] : []

            if let selectedPDFFile = state.selectedPDFFile,
               selectedPDFFile.persistentModelID == change.fileID,
               selectedPDFFile.availability == .missing || confirmedDeletedFileIDs.contains(change.fileID) {
                closeMissingPDF(state)
            }
        } else {
            confirmedDeletedFileIDs = []
            if state.selectedPDFFile?.availability == .missing {
                closeMissingPDF(state)
            }
        }

        do {
            let pdfFiles = try modelContext.fetch(FetchDescriptor<PDFFile>())
            try deleteMissingFiles(modelContext, pdfFiles, confirmedDeletedFileIDs)

            let existingPDFFiles = try modelContext.fetch(FetchDescriptor<PDFFile>()).filter {
                $0.availability != .missing
            }

            monitor.sync(existingPDFFiles) { [weak state, weak monitor] change in
                guard let state, let monitor else { return }
                synchronizeLibraryFiles(state, modelContext, monitor, change)
            }
        } catch {
            handle(error, "Library Could Not Be Synchronized", "Synchronize PDF library", state, change?.url)
        }
    }

    static func delete(
        _ modelContext: ModelContext,
        _ url: URL,
        _ resolvedURL: URL,
        _ removeFile: ((URL) throws -> Void)? = nil
    ) throws {
        if let removeFile {
            try removeFile(resolvedURL)
        } else {
            try FileIO.delete(resolvedURL)
        }

        do {
            try PDFFileService.delete(modelContext, url)
        } catch {
            AppLogger.recordDiagnostic(
                "The file was deleted, but its library entry could not be removed. Automatic synchronization will retry the cleanup.",
                "Delete PDF library entry",
                resolvedURL
            )
            throw error
        }
    }

    static func deleteMissingFiles(
        _ modelContext: ModelContext,
        _ pdfFiles: [PDFFile],
        _ confirmedDeletedFileIDs: Set<PersistentIdentifier> = []
    ) throws {
        var needsSave = false

        let missingPDFFiles = pdfFiles.filter {
            $0.availability == .missing
                || (confirmedDeletedFileIDs.contains($0.persistentModelID)
                    && FileIO.exists($0.resolvedURL) == false)
        }

        PDFTagService.deleteTagsOrphanedByDeleting(
            missingPDFFiles,
            in: modelContext
        )

        for pdfFile in missingPDFFiles {
            modelContext.delete(pdfFile)
            needsSave = true
        }

        if needsSave {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw AppError.system(
                    "The library could not be synchronized.",
                    error.localizedDescription,
                    error
                )
            }
        }
    }

    static func matches(
        _ pdfFile: PDFFile,
        _ searchText: String,
        _ mode: SearchMode
    ) -> Bool {
        let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.isEmpty == false else {
            return true
        }

        let titleMatches = pdfFile.resolvedURL.lastPathComponent.localizedCaseInsensitiveContains(searchText)
        let tagMatches = pdfFile.tags.contains {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        return switch mode {
        case .all:
            titleMatches || tagMatches
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
        let pageBounds = page.bounds(for: .cropBox)
        let rotation = (page.rotation % 360 + 360) % 360
        let swapsDimensions = rotation == 90 || rotation == 270
        
        let scale = dpi / 72
        
        let width = Int(ceil((swapsDimensions ? pageBounds.height : pageBounds.width) * scale))
        
        let height = Int(ceil((swapsDimensions ? pageBounds.width : pageBounds.height) * scale))

        guard
            width > 0, height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue )
        else {
            throw AppError.textRecognitionFailed("An image could not be created from this PDF page.")
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        context.saveGState()
        
        context.scaleBy(x: scale, y: scale)
        
        page.draw(with: .cropBox, to: context)
        
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw AppError.textRecognitionFailed("This PDF page could not be prepared for text recognition.")
        }

        return image
    }

    private static func closeMissingPDF(_ state: LibraryViewState) {
        state.cancelTranslation()
        state.selectedPDFFile = nil
    }

    private static func handle(
        _ error: Error,
        _ title: String,
        _ operation: String,
        _ state: LibraryViewState,
        _ targetURL: URL? = nil
    ) {
        guard let appError = AppError.presentable(error), appError.isCancellation == false else {
            return
        }

        AppLogger.record(appError, operation, targetURL)
        state.errorTitle = title
        state.appError = appError
    }
}
