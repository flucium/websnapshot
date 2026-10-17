import Foundation
import SwiftData
import AppKit
import Translation

@MainActor
final class LibraryViewService {
    static func importPDFs(_ state: LibraryViewState, _ modelContext: ModelContext, sync: LibrarySyncService) {

        guard let sourceURLs = importPDFsPanel(), sourceURLs.isEmpty == false else {
            return
        }

        do {

            let settings = try modelContext.fetch(FetchDescriptor<StorageSettings>())

            let destinationDirectory: URL?

            switch StorageSettingsService.storage(settings) {
            case .fixed:
                destinationDirectory = try StorageSettingsService.fixedStorageURL(settings, sync: sync)

                if destinationDirectory == nil {
                    throw AppError.error("Choose a storage folder in Settings before importing.")
                }

            case .flexibility:
                let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first

                destinationDirectory = directoryPanel(documents, "Choose Import Folder",  "Import")
            }

            guard let destinationDirectory else {
                return
            }

            importPDFs(state, modelContext, sourceURLs, destinationDirectory, sync: sync)
        } catch {
            handle(error, "PDFs Could Not Be Imported", "Import PDFs", state)
        }
    }

    static func importPDFs(_ state: LibraryViewState, _ modelContext: ModelContext, _ sourceURLs: [URL], _ destinationDirectory: URL, sync: LibrarySyncService) {
        guard sourceURLs.isEmpty == false else {
            return
        }

        var importedURLs: [URL] = []

        var failures: [(url: URL, error: AppError)] = []

        for sourceURL in sourceURLs {
            do {
                let destination = try LibraryService.importPDF(sourceURL, destinationDirectory, modelContext, sync: sync)
                importedURLs.append(destination)
            } catch {
                guard let appError = AppError.presentable(error) else {
                    continue
                }

                AppLogger.record(appError, "Import PDF", sourceURL)
                failures.append((sourceURL, appError))
            }
        }

        if let destination = importedURLs.last {
            let registeredPDF = try? modelContext.fetch(FetchDescriptor<PDFFile>()).first {
                $0.url.standardizedFileURL == destination.standardizedFileURL
            }

            state.searchText = ""

            state.selectedTag = .all

            state.selectedPDFRowID = registeredPDF?.persistentModelID
        }

        state.appError = nil

        guard let firstFailure = failures.first else {
            return
        }

        if sourceURLs.count == 1 {
            state.errorTitle = "PDF Could Not Be Imported"
            state.appError = firstFailure.error
            return
        }

        let messages = failures.map {
            "\($0.url.lastPathComponent): \($0.error.userMessage)"
        }.joined(separator: "\n")

        state.errorTitle = importedURLs.isEmpty ? "PDFs Could Not Be Imported" : "Some PDFs Could Not Be Imported"

        state.appError = .error("\(importedURLs.count) of \(sourceURLs.count) PDFs were imported.\n\n\(messages)")
    }

    static func exportPDF(_ state: LibraryViewState, _ pdfFile: PDFFile) {

        let sourceURL = pdfFile.resolvedURL

        guard let destinationURL = exportPDFPanel(sourceURL.lastPathComponent) else {
            return
        }

        do {
            try LibraryService.exportPDF(sourceURL,  destinationURL)

            state.appError = nil

        } catch {

            handle(error, "PDF Could Not Be Exported", "Export PDF", state, sourceURL)

        }
    }

    static func startTranslation(_ state: LibraryViewState, _ targetLanguage: TranslationLanguage) {

        guard let selectedPDFFile = state.selectedPDFFile else {
            return
        }

        state.appError = nil

        let request = state.beginTranslation(selectedPDFFile, targetLanguage)

        state.translationPreparationTask = Task { @MainActor in

            do {
                try Task.checkCancellation()

                let text = try await LibraryService.textForTranslation(request.url, request.pageIndex)

                try Task.checkCancellation()

                state.prepareTranslation(text, for: request)
            } catch {
                guard state.isCurrentTranslation(request) else {
                    return
                }

                state.finishTranslation(request)

                if selectedPDFFile.availability == .missing {
                    closeMissingPDF(state)
                }

                handle(error, "Text Could Not Be Prepared", "Prepare PDF text", state, request.url)
            }
        }
    }

    static func translate(_ state: LibraryViewState,_ session: TranslationSession,_ request: LibraryViewState.TranslationRequest) async {

        guard let text = request.text, state.isCurrentTranslation(request), !Task.isCancelled else {
            return
        }

        do {
            let translated = try await Translation.translate(session, text)

            try Task.checkCancellation()

            state.completeTranslation(translated, for: request)
        } catch {
            guard state.isCurrentTranslation(request) else {
                return
            }

            handle(error, "Translation Could Not Be Completed", "Translate PDF text", state, request.url)

            state.finishTranslation(request)
        }
    }

    static func deletePDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, sync: LibrarySyncService) {
        do {
            try LibraryService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL, sync: sync)

            state.selectedPDFFile = nil

            state.appError = nil
        } catch {
            handle(error, "PDF Could Not Be Deleted", "Delete PDF", state, pdfFile.resolvedURL)
        }
    }

    static func deleteDisplayedPDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, sync: LibrarySyncService) {

        let url = pdfFile.url

        let resolvedURL = pdfFile.resolvedURL

        state.cancelTranslation()

        state.selectedPDFFile = nil

        state.appError = nil

        Task { @MainActor in

            await Task.yield()

            do {
                try LibraryService.delete(modelContext, url, resolvedURL, sync: sync)
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

    static func synchronizeLibraryFiles(_ state: LibraryViewState,_ modelContext: ModelContext,_ monitor: LibraryPDFFileMonitor, sync: LibrarySyncService, _ change: LibraryPDFFileMonitor.Change? = nil) {

        if sync.state.isSwitching || LibrarySyncService.isEnabled(modelContext) {

            monitor.stop()

            if let selected = state.selectedPDFFile, selected.isDeleted || selected.modelContext == nil {
                closeMissingPDF(state)
            }

            return
        }

        let confirmedDeletedFileIDs: Set<PersistentIdentifier>

        if let change {
            confirmedDeletedFileIDs = change.wasDeleted && FileIO.exists(change.url) == false ? [change.fileID] : []

            if let selectedPDFFile = state.selectedPDFFile, selectedPDFFile.persistentModelID == change.fileID, selectedPDFFile.availability == .missing || confirmedDeletedFileIDs.contains(change.fileID) {

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

            try PDFFileService.deleteMissingFiles(modelContext, pdfFiles, sync: sync, confirmedDeletedFileIDs)

            let existingPDFFiles = try modelContext.fetch(FetchDescriptor<PDFFile>()).filter {
                $0.availability != .missing
            }

            monitor.sync(existingPDFFiles) { [weak state, weak monitor] change in

                guard let state, let monitor else {
                    return
                }

                synchronizeLibraryFiles(state, modelContext, monitor, sync: sync, change)
            }

        } catch {
            handle(error, "Library Could Not Be Synchronized", "Synchronize PDF library", state, change?.url)
        }
    }

    static func openPDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, sync: LibrarySyncService) {

        if pdfFile.syncRelativePath != nil {

            let id = pdfFile.persistentModelID

            guard state.downloadingPDFs.insert(id).inserted else {
                return
            }

            Task {
                @MainActor in

                defer {
                    state.downloadingPDFs.remove(id)
                }

                do {
                    try await sync.download(pdfFile, modelContext)

                    guard !pdfFile.isDeleted, pdfFile.modelContext != nil, !sync.state.isSwitching else {
                        return
                    }

                    state.selectedPDFRowID = id

                    state.selectedPDFFile = pdfFile

                } catch {

                    state.errorTitle = "PDF Could Not Be Downloaded"

                    state.appError = AppError(error)
                }

            }

            return

        }

        state.selectedPDFRowID = pdfFile.persistentModelID

        state.selectedPDFFile = pdfFile

    }

    static func closeDisplayedPDF(_ state: LibraryViewState) {
        state.cancelTranslation()

        Task {

            @MainActor in

            await Task.yield()

            state.selectedPDFFile = nil
        }
    }

    static func scheduleSynchronizeLibraryFiles(_ state: LibraryViewState, _ modelContext: ModelContext, _ monitor: LibraryPDFFileMonitor, sync: LibrarySyncService) {
        Task {

            @MainActor in

            await synchronizeLibraryFilesAfterViewUpdate(state, modelContext, monitor, sync: sync)
        }
    }

    static func synchronizeLibraryFilesAfterViewUpdate(_ state: LibraryViewState, _ modelContext: ModelContext, _ monitor: LibraryPDFFileMonitor, sync: LibrarySyncService) async {
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            return
        }

        synchronizeLibraryFiles(state, modelContext, monitor, sync: sync)
    }

    private static func closeMissingPDF(_ state: LibraryViewState) {
        state.cancelTranslation()
        state.selectedPDFFile = nil
    }

    private static func handle( _ error: Error, _ title: String, _ operation: String, _ state: LibraryViewState, _ targetURL: URL? = nil ) {

        guard let appError = AppError.presentable(error), appError.isCancellation == false else {
            return
        }

        AppLogger.record(appError, operation, targetURL)

        state.errorTitle = title

        state.appError = appError
    }
}
