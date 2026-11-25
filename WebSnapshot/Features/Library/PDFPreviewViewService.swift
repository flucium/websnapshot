import Foundation
import PDFKit

@MainActor
final class PDFPreviewViewService {
    static func loadPreview(_ pdfPreviewViewState: PDFPreviewViewState, _ pdfPreviewRequest: PDFPreviewRequest) async {
        do {

            let url = try pdfPreviewRequest.url.get()

            let syncFolder = pdfPreviewRequest.syncFolder

            let task = Task.detached(priority: .userInitiated) {
                try Self.renderFirstPage(url, syncFolder)
            }

            let images = try await withTaskCancellationHandler {
                try await task.value
            } onCancel: {
                task.cancel()
            }

            try Task.checkCancellation()

            pdfPreviewViewState.phase = .ready(images)
        } catch {
            guard !Task.isCancelled else {
                return
            }

            pdfPreviewViewState.phase = .failed(AppError(error))
        }
    }

    private nonisolated static func renderFirstPage(_ url: URL, _ syncFolder: URL?) throws -> PDFPreviewViewState.PreviewImages {
        try Task.checkCancellation()

        return try withPDFPreviewAccess(url, syncFolder) {
            try SyncFileStore.coordinatedRead(url) {
                file in

                try Task.checkCancellation()

                guard let document = PDFDocument(url: file), !document.isLocked, let page = document.page(at: 0) else {
                    throw AppError.invalidFileType("The first page of this PDF could not be read.")
                }

                let fullPage = try PDFContentService.render(page, 144)

                guard fullPage.height > fullPage.width * 2 else {
                    return PDFPreviewViewState.PreviewImages(fullPage: fullPage, pageTop: nil)
                }

                try Task.checkCancellation()

                let pageTop = try PDFContentService.render(page, 144, maximumHeightRatio: 1.15)

                return PDFPreviewViewState.PreviewImages(fullPage: fullPage, pageTop: pageTop)
            }
        }
    }
}

extension PDFPreviewRequest {
    init(_ pdfFile: PDFFile, _ storageSettings: StorageSettings?) {
        let isSynced = pdfFile.syncRelativePath != nil

        let syncFolder: URL?

        if isSynced, let storageSettings, storageSettings.syncEnabled {

            syncFolder = try? LibrarySyncSettings.folderURL(storageSettings)

        } else {
            syncFolder = nil
        }

        let resolution = Result {
            try pdfFile.resolveURL()
        }.mapError {
            AppError($0)
        }

        let resolvedURL = try? resolution.get()

        let fileName = (resolvedURL ?? pdfFile.url).lastPathComponent

        let needsDownload: Bool

        if let resolvedURL {
            needsDownload = Self.isWaitingForDownload(resolvedURL, syncFolder, isSynced)
        } else {
            needsDownload = false
        }

        self.init(fileName: fileName, url: resolution, syncFolder: syncFolder, needsDownload: needsDownload)
    }

    private static func isWaitingForDownload(_ url: URL, _ syncFolder: URL?, _ isSynced: Bool) -> Bool {
        withPDFPreviewAccess(url, syncFolder) {

            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus {
                return status == .notDownloaded
            }

            return isSynced && FileIO.availability(url) != .available
        }
    }
}

private nonisolated func withPDFPreviewAccess<T>(_ url: URL, _ syncFolder: URL?, _ operation: () throws -> T) rethrows -> T {

    let accessingFolder = syncFolder?.startAccessingSecurityScopedResource() == true

    let accessingFile = url.startAccessingSecurityScopedResource()

    defer {
        if accessingFile {
            url.stopAccessingSecurityScopedResource()
        }

        if accessingFolder {
            syncFolder?.stopAccessingSecurityScopedResource()
        }
    }

    return try operation()
}
