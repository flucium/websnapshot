import Foundation
import SwiftData
import AppKit
import Translation

@MainActor
final class LibraryViewService {
        static func importPDFs(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ librarySyncService: LibrarySyncService) {

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

            importPDFs(libraryViewState, modelContext, sourceURLs, destinationDirectory, librarySyncService)
        } catch {
            handle(error, "PDFs Could Not Be Imported", "Import PDFs", libraryViewState)
        }
    }

    static func importPDFs(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ sourceURLs: [URL], _ destinationDirectory: URL, _ librarySyncService: LibrarySyncService) {
        
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

            libraryViewState.searchText = ""

            libraryViewState.selectedTag = .all

            libraryViewState.selectedPDFRowID = registeredPDF?.persistentModelID
        }

        libraryViewState.appError = nil

        guard let firstFailure = failures.first else {
            return
        }

        if sourceURLs.count == 1 {
            libraryViewState.errorTitle = "PDF Could Not Be Imported"
            
            libraryViewState.appError = firstFailure.error
            
            return
        }

        let messages = failures.map {
            "\($0.url.lastPathComponent): \($0.error.userMessage)"
        }.joined(separator: "\n")

        libraryViewState.errorTitle = importedURLs.isEmpty ? "PDFs Could Not Be Imported" : "Some PDFs Could Not Be Imported"

        libraryViewState.appError = .error("\(importedURLs.count) of \(sourceURLs.count) PDFs were imported.\n\n\(messages)")
    }

    static func exportPDF(_ libraryViewState: LibraryViewState, _ pdfFile: PDFFile) {

        let sourceURL = pdfFile.resolvedURL

        guard let destinationURL = exportPDFPanel(sourceURL.lastPathComponent) else {
            return
        }

        do {
            try LibraryService.exportPDF(sourceURL,  destinationURL)

            libraryViewState.appError = nil

        } catch {

            handle(error, "PDF Could Not Be Exported", "Export PDF", libraryViewState, sourceURL)

        }
    }

    static func startTranslation(_ libraryViewState: LibraryViewState, _ targetLanguage: TranslationLanguage) {

        guard let selectedPDFFile = libraryViewState.selectedPDFFile, libraryViewState.displayedPDFData != nil else {
            return
        }

        libraryViewState.appError = nil

        let request = libraryViewState.beginTranslation(selectedPDFFile, targetLanguage)

        libraryViewState.translationPreparationTask = Task { @MainActor in

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

                libraryViewState.prepareTranslation(text, for: request)
            } catch {
                guard libraryViewState.isCurrentTranslation(request) else {
                    return
                }

                libraryViewState.finishTranslation(request)

                if selectedPDFFile.availability == .missing {
                    closeMissingPDF(libraryViewState)
                }

                handle(error, "Text Could Not Be Prepared", "Prepare PDF text", libraryViewState, request.url)
            }
        }
    }

    static func translate(_ libraryViewState: LibraryViewState,_ session: TranslationSession,_ request: LibraryViewState.TranslationRequest) async {

        guard let text = request.text, libraryViewState.isCurrentTranslation(request), !Task.isCancelled else {
            return
        }

        do {
            let translated = try await Translation.translate(session, text)

            try Task.checkCancellation()

            libraryViewState.completeTranslation(translated, for: request)
        } catch {
            guard libraryViewState.isCurrentTranslation(request) else {
                return
            }

            handle(error, "Translation Could Not Be Completed", "Translate PDF text", libraryViewState, request.url)

            libraryViewState.finishTranslation(request)
        }
    }

    static func requestDeletion(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        do {
            let settings = try LibrarySyncSettings.settings(modelContext)

            if settings?.confirmBeforeDeleting ?? true {
                libraryViewState.pendingDeletionPDFFile = pdfFile

                libraryViewState.showDeleteConfirmation = true
            } else {
                deleteRequestedPDF(libraryViewState, modelContext, pdfFile, librarySyncService)
            }
        } catch {
            handle(error, "PDF Could Not Be Deleted", "Load deletion settings", libraryViewState, pdfFile.resolvedURL)
        }
    }

    static func confirmDeletion(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ librarySyncService: LibrarySyncService) {
        guard let pdfFile = libraryViewState.pendingDeletionPDFFile else {
            return
        }

        libraryViewState.pendingDeletionPDFFile = nil

        libraryViewState.showDeleteConfirmation = false

        deleteRequestedPDF(libraryViewState, modelContext, pdfFile, librarySyncService)
    }

    private static func deleteRequestedPDF(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        guard pdfFile.modelContext != nil, !pdfFile.isDeleted else {
            return
        }

        if libraryViewState.selectedPDFFile?.persistentModelID == pdfFile.persistentModelID {
            deleteDisplayedPDF(libraryViewState, modelContext, pdfFile, librarySyncService)
        } else {
            deletePDF(libraryViewState, modelContext, pdfFile, librarySyncService)
        }
    }

    static func deletePDF(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        do {
            try LibraryService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL, librarySyncService)

            libraryViewState.selectedPDFFile = nil

            libraryViewState.appError = nil
        } catch {
            handle(error, "PDF Could Not Be Deleted", "Delete PDF", libraryViewState, pdfFile.resolvedURL)
        }
    }

    static func deleteDisplayedPDF(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {

        let url = pdfFile.url

        let resolvedURL = pdfFile.resolvedURL

        libraryViewState.cancelTranslation()

        libraryViewState.selectedPDFFile = nil

        libraryViewState.appError = nil

        Task { @MainActor in

            await Task.yield()

            do {
                try LibraryService.delete(modelContext, url, resolvedURL, librarySyncService)
            } catch {
                handle(error, "PDF Could Not Be Deleted", "Delete PDF", libraryViewState, resolvedURL)
            }
        }
    }

    static func copyFilePath(_ libraryViewState: LibraryViewState, _ pdfFile: PDFFile) {

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

            libraryViewState.appError = nil
        } catch {
            handle(error, "File Path Could Not Be Copied", "Copy PDF path", libraryViewState, resolvedURL)
        }
    }

    static func synchronizeLibraryFiles(_ libraryViewState: LibraryViewState,_ modelContext: ModelContext,_ libraryPDFFileMonitor: LibraryPDFFileMonitor, _ librarySyncService: LibrarySyncService, _ change: LibraryPDFFileMonitor.Change? = nil, contentService: LibraryContentService? = nil) {

        do {
            let pdfFiles = try modelContext.fetch(FetchDescriptor<PDFFile>())

            defer {
                refreshFileLocations(libraryViewState, pdfFiles.filter {
                    !$0.isDeleted && $0.modelContext != nil
                })
            }

            if librarySyncService.state.isSwitching || LibrarySyncService.isEnabled(modelContext) {

                libraryPDFFileMonitor.stop()

                if let selected = libraryViewState.selectedPDFFile, selected.isDeleted || selected.modelContext == nil {
                    closeMissingPDF(libraryViewState)
                }

                return
            }

            if let change, change.wasModified, FileIO.exists(change.url), let pdfFile = modelContext.model(for: change.fileID) as? PDFFile, pdfFile.modelContext != nil, !pdfFile.isDeleted {
                refreshDisplayedPDF(libraryViewState)

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

                if let selectedPDFFile = libraryViewState.selectedPDFFile, selectedPDFFile.persistentModelID == change.fileID, selectedPDFFile.availability == .missing || confirmedDeletedFileIDs.contains(change.fileID) {

                    closeMissingPDF(libraryViewState)

                }

            } else {
                confirmedDeletedFileIDs = []

                if libraryViewState.selectedPDFFile?.availability == .missing {
                    closeMissingPDF(libraryViewState)
                }
            }

            try LibraryService.deleteMissingFiles(modelContext, pdfFiles, librarySyncService, confirmedDeletedFileIDs)

            let existingPDFFiles = pdfFiles.filter {
                !$0.isDeleted && $0.modelContext != nil
            }

            libraryPDFFileMonitor.sync(existingPDFFiles) { [weak libraryViewState, weak libraryPDFFileMonitor] change in

                guard let libraryViewState, let libraryPDFFileMonitor else {
                    return
                }

                synchronizeLibraryFiles(libraryViewState, modelContext, libraryPDFFileMonitor, librarySyncService, change, contentService: contentService)
            }

        } catch {
            handle(error, "Library Could Not Be Synchronized", "Synchronize PDF library", libraryViewState, change?.url)
        }
    }

    private static func refreshFileLocations(_ libraryViewState: LibraryViewState, _ pdfFiles: [PDFFile]) {
        let locations = Dictionary(pdfFiles.map {
            pdfFile in

            (pdfFile.persistentModelID, LibraryViewState.FileLocation(source: LibraryViewState.FileSource(pdfFile), url: pdfFile.resolvedURL, availability: pdfFile.availability))
        }, uniquingKeysWith: {
            first, _ in first
        })

        libraryViewState.updateFileLocations(locations)
    }

    static func openPDF(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {

        let request = libraryViewState.beginOpeningPDF()

        if pdfFile.syncRelativePath != nil {

            let id = pdfFile.persistentModelID

            libraryViewState.downloadingPDFs.insert(id)

            libraryViewState.openPDFTask = Task {
                @MainActor in

                defer {
                    libraryViewState.finishOpeningPDF(request)
                }

                do {
                    try await librarySyncService.download(pdfFile, modelContext)

                    guard libraryViewState.isCurrentOpenRequest(request), !Task.isCancelled, !pdfFile.isDeleted, pdfFile.modelContext != nil, !librarySyncService.state.isSwitching else {
                        return
                    }

                    libraryViewState.completeOpeningPDF(pdfFile, for: request)

                    refreshDisplayedPDF(libraryViewState)

                } catch {

                    guard libraryViewState.isCurrentOpenRequest(request), !Task.isCancelled else {
                        return
                    }

                    libraryViewState.errorTitle = "PDF Could Not Be Downloaded"

                    libraryViewState.appError = AppError(error)
                }

            }

            return

        }

        libraryViewState.completeOpeningPDF(pdfFile, for: request)

        refreshDisplayedPDF(libraryViewState)

    }

    static func closeDisplayedPDF(_ libraryViewState: LibraryViewState) {
        let request = libraryViewState.beginOpeningPDF()

        libraryViewState.cancelTranslation()

        Task {

            @MainActor in

            await Task.yield()

            guard libraryViewState.isCurrentOpenRequest(request) else {
                return
            }

            libraryViewState.finishOpeningPDF(request)

            libraryViewState.selectedPDFFile = nil
        }
    }

    static func synchronizeLibraryFilesAfterViewUpdate(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ libraryPDFFileMonitor: LibraryPDFFileMonitor,  _ librarySyncService: LibrarySyncService, contentService: LibraryContentService? = nil) async {
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            return
        }

        synchronizeLibraryFiles(libraryViewState, modelContext, libraryPDFFileMonitor, librarySyncService, contentService: contentService)
    }

    static func refreshDisplayedPDF(_ libraryViewState: LibraryViewState) {
        guard let pdfFile = libraryViewState.selectedPDFFile else {
            return
        }

        guard !pdfFile.isDeleted, pdfFile.modelContext != nil else {
            closeMissingPDF(libraryViewState)
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

            guard libraryViewState.displayedPDFURL != url || libraryViewState.displayedPDFFingerprint != fingerprint else {
                return
            }

            let data = try Data(contentsOf: url)

            guard try PDFContentService.fingerprint(url) == fingerprint else {
                return
            }

            libraryViewState.displayPDF(data, url, fingerprint)
        } catch {
            if pdfFile.availability == .missing {
                closeMissingPDF(libraryViewState)
            }

            if libraryViewState.appError == nil {
                handle(error, "PDF Could Not Be Opened", "Refresh displayed PDF", libraryViewState, url)
            }
        }
    }

    private static func closeMissingPDF(_ libraryViewState: LibraryViewState) {
        libraryViewState.cancelOpeningPDF()
        libraryViewState.cancelTranslation()
        libraryViewState.selectedPDFFile = nil
    }

    private static func handle( _ error: Error, _ title: String, _ operation: String, _ libraryViewState: LibraryViewState, _ targetURL: URL? = nil ) {

        guard let appError = AppError.presentable(error), appError.isCancellation == false else {
            return
        }

        AppLogger.record(appError, operation, targetURL)

        libraryViewState.errorTitle = title

        libraryViewState.appError = appError
    }
}
