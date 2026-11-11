import Foundation
import SwiftData
import AppKit
import Translation

@MainActor
final class LibraryViewService {
    static func importPDFs(_ state: LibraryViewState, _ modelContext: ModelContext, _ librarySyncService: LibrarySyncService) {

        guard let sourceURLs = importPDFsPanel(), sourceURLs.isEmpty == false else {
            return
        }

        do {

            let settings = try modelContext.fetch(FetchDescriptor<StorageSettings>())

            let destinationDirectory: URL?

            switch StorageSettingsService.storage(settings) {
            case .fixed:
                destinationDirectory = try StorageSettingsService.fixedStorageURL(settings, librarySyncService)

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

            importPDFs(state, modelContext, sourceURLs, destinationDirectory, librarySyncService)
        } catch {
            handle(error, "PDFs Could Not Be Imported", "Import PDFs", state)
        }
    }

    static func importPDFs(_ state: LibraryViewState, _ modelContext: ModelContext, _ sourceURLs: [URL], _ destinationDirectory: URL, _ librarySyncService: LibrarySyncService) {
        
        guard sourceURLs.isEmpty == false else {
            return
        }

        var importedURLs: [URL] = []

        var failures: [(url: URL, error: AppError)] = []

        for sourceURL in sourceURLs {
            do {
                let destination = try LibraryService.importPDF(sourceURL, destinationDirectory, modelContext, librarySyncService)
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

        guard let selectedPDFFile = state.selectedPDFFile, state.displayedPDFData != nil else {
            return
        }

        state.appError = nil

        let request = state.beginTranslation(selectedPDFFile, targetLanguage)

        state.translationPreparationTask = Task { @MainActor in

            do {
                try Task.checkCancellation()

                guard let data = request.data else {
                    return
                }

                let text = try await PDFContentService().text(data, pageIndex: request.pageIndex)

                guard !text.isEmpty else {
                    throw AppError.textRecognitionFailed("No text was found on the displayed PDF page.")
                }

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

    static func requestDeletion(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        do {
            let settings = try LibrarySyncSettings.settings(modelContext)

            if settings?.confirmBeforeDeleting ?? true {
                state.pendingDeletionPDFFile = pdfFile

                state.showDeleteConfirmation = true
            } else {
                deleteRequestedPDF(state, modelContext, pdfFile, librarySyncService)
            }
        } catch {
            handle(error, "PDF Could Not Be Deleted", "Load deletion settings", state, pdfFile.resolvedURL)
        }
    }

    static func confirmDeletion(_ state: LibraryViewState, _ modelContext: ModelContext, _ librarySyncService: LibrarySyncService) {
        guard let pdfFile = state.pendingDeletionPDFFile else {
            return
        }

        state.pendingDeletionPDFFile = nil

        state.showDeleteConfirmation = false

        deleteRequestedPDF(state, modelContext, pdfFile, librarySyncService)
    }

    private static func deleteRequestedPDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        guard pdfFile.modelContext != nil, !pdfFile.isDeleted else {
            return
        }

        if state.selectedPDFFile?.persistentModelID == pdfFile.persistentModelID {
            deleteDisplayedPDF(state, modelContext, pdfFile, librarySyncService)
        } else {
            deletePDF(state, modelContext, pdfFile, librarySyncService)
        }
    }

    static func deletePDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        do {
            try LibraryService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL, librarySyncService)

            state.selectedPDFFile = nil

            state.appError = nil
        } catch {
            handle(error, "PDF Could Not Be Deleted", "Delete PDF", state, pdfFile.resolvedURL)
        }
    }

    static func deleteDisplayedPDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {

        let url = pdfFile.url

        let resolvedURL = pdfFile.resolvedURL

        state.cancelTranslation()

        state.selectedPDFFile = nil

        state.appError = nil

        Task { @MainActor in

            await Task.yield()

            do {
                try LibraryService.delete(modelContext, url, resolvedURL, librarySyncService)
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

    static func synchronizeLibraryFiles(_ state: LibraryViewState,_ modelContext: ModelContext,_ libraryPDFFileMonitor: LibraryPDFFileMonitor, _ librarySyncService: LibrarySyncService, _ change: LibraryPDFFileMonitor.Change? = nil, contentService: LibraryContentService? = nil) {

        do {
            let pdfFiles = try modelContext.fetch(FetchDescriptor<PDFFile>())

            defer {
                refreshFileLocations(state, pdfFiles.filter {
                    !$0.isDeleted && $0.modelContext != nil
                })
            }

            if librarySyncService.state.isSwitching || LibrarySyncService.isEnabled(modelContext) {

                libraryPDFFileMonitor.stop()

                if let selected = state.selectedPDFFile, selected.isDeleted || selected.modelContext == nil {
                    closeMissingPDF(state)
                }

                return
            }

            if let change, change.wasModified, FileIO.exists(change.url), let pdfFile = modelContext.model(for: change.fileID) as? PDFFile, pdfFile.modelContext != nil, !pdfFile.isDeleted {
                refreshDisplayedPDF(state)

                if let contentService {
                    Task {
                        await contentService.index([pdfFile], modelContext, pruneFailures: false)
                    }
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

            try LibraryService.deleteMissingFiles(modelContext, pdfFiles, librarySyncService, confirmedDeletedFileIDs)

            let existingPDFFiles = pdfFiles.filter {
                !$0.isDeleted && $0.modelContext != nil
            }

            libraryPDFFileMonitor.sync(existingPDFFiles) { [weak state, weak libraryPDFFileMonitor] change in

                guard let state, let libraryPDFFileMonitor else {
                    return
                }

                synchronizeLibraryFiles(state, modelContext, libraryPDFFileMonitor, librarySyncService, change, contentService: contentService)
            }

        } catch {
            handle(error, "Library Could Not Be Synchronized", "Synchronize PDF library", state, change?.url)
        }
    }

    private static func refreshFileLocations(_ state: LibraryViewState, _ pdfFiles: [PDFFile]) {
        let locations = Dictionary(pdfFiles.map {
            pdfFile in

            (pdfFile.persistentModelID, LibraryViewState.FileLocation(source: LibraryViewState.FileSource(pdfFile), url: pdfFile.resolvedURL, availability: pdfFile.availability))
        }, uniquingKeysWith: {
            first, _ in first
        })

        state.updateFileLocations(locations)
    }

    static func openPDF(_ state: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {

        let request = state.beginOpeningPDF()

        if pdfFile.syncRelativePath != nil {

            let id = pdfFile.persistentModelID

            state.downloadingPDFs.insert(id)

            state.openPDFTask = Task {
                @MainActor in

                defer {
                    state.finishOpeningPDF(request)
                }

                do {
                    try await librarySyncService.download(pdfFile, modelContext)

                    guard state.isCurrentOpenRequest(request), !Task.isCancelled, !pdfFile.isDeleted, pdfFile.modelContext != nil, !librarySyncService.state.isSwitching else {
                        return
                    }

                    state.completeOpeningPDF(pdfFile, for: request)

                    refreshDisplayedPDF(state)

                } catch {

                    guard state.isCurrentOpenRequest(request), !Task.isCancelled else {
                        return
                    }

                    state.errorTitle = "PDF Could Not Be Downloaded"

                    state.appError = AppError(error)
                }

            }

            return

        }

        state.completeOpeningPDF(pdfFile, for: request)

        refreshDisplayedPDF(state)

    }

    static func closeDisplayedPDF(_ state: LibraryViewState) {
        let request = state.beginOpeningPDF()

        state.cancelTranslation()

        Task {

            @MainActor in

            await Task.yield()

            guard state.isCurrentOpenRequest(request) else {
                return
            }

            state.finishOpeningPDF(request)

            state.selectedPDFFile = nil
        }
    }

    static func synchronizeLibraryFilesAfterViewUpdate(_ state: LibraryViewState, _ modelContext: ModelContext, _ libraryPDFFileMonitor: LibraryPDFFileMonitor,  _ librarySyncService: LibrarySyncService, contentService: LibraryContentService? = nil) async {
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            return
        }

        synchronizeLibraryFiles(state, modelContext, libraryPDFFileMonitor, librarySyncService, contentService: contentService)
    }

    static func refreshDisplayedPDF(_ state: LibraryViewState) {
        guard let pdfFile = state.selectedPDFFile else {
            return
        }

        guard !pdfFile.isDeleted, pdfFile.modelContext != nil else {
            closeMissingPDF(state)
            return
        }

        let url = pdfFile.resolvedURL

        let accessing = url.startAccessingSecurityScopedResource()

        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let fingerprint = try PDFContentService.fingerprint(url)

            guard state.displayedPDFURL != url || state.displayedPDFFingerprint != fingerprint else {
                return
            }

            let data = try Data(contentsOf: url)

            guard try PDFContentService.fingerprint(url) == fingerprint else {
                return
            }

            state.displayPDF(data, url, fingerprint)
        } catch {
            if pdfFile.availability == .missing {
                closeMissingPDF(state)
            }

            if state.appError == nil {
                handle(error, "PDF Could Not Be Opened", "Refresh displayed PDF", state, url)
            }
        }
    }

    private static func closeMissingPDF(_ state: LibraryViewState) {
        state.cancelOpeningPDF()
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
