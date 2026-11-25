import SwiftUI
import PDFKit
import CoreGraphics

struct PDFPreviewRequest: Identifiable {
    let id = UUID()
    
    let fileName: String
    
    let url: Result<URL, AppError>
    
    let syncFolder: URL?
    
    let needsDownload: Bool

    init(_ pdfFile: PDFFile, _ storageSettings: StorageSettings?) {
        let isSynced = pdfFile.syncRelativePath != nil

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

        url = resolution
        
        fileName = (resolvedURL ?? pdfFile.url).lastPathComponent

        if let resolvedURL {
            needsDownload = Self.isWaitingForDownload(resolvedURL, syncFolder, isSynced)
        } else {
            needsDownload = false
        }
    }

    private static func isWaitingForDownload(_ url: URL, _ syncFolder: URL?, _ isSynced: Bool) -> Bool {
        withPDFPreviewAccess(url, syncFolder) {
            
            if let status = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus{
                return status == .notDownloaded
            }

            return isSynced && FileIO.availability(url) != .available
        }
    }
}


struct PDFPreviewView: View {

    private nonisolated struct PreviewImages: Sendable {
        let fullPage: CGImage
        let pageTop: CGImage?
    }
    
    private enum Phase {
        case loading
        case ready(PreviewImages)
        case failed(AppError)
    }

    

    @State private var phase: Phase = .loading

    @State private var showsFullPage = false

    private let pdfPreviewRequest: PDFPreviewRequest

    static let windowID = "pdf-preview"
    

    init(_ pdfPreviewRequest: PDFPreviewRequest) {
        self.pdfPreviewRequest = pdfPreviewRequest
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                
                Text(pdfPreviewRequest.fileName)
                    .font(.headline)
                    .lineLimit(1)

                if case .ready(let images) = phase, images.pageTop != nil {
                    Spacer(minLength: 8)

                    Button(showsFullPage ? "Show Page Top" : "Show Full Page") {
                        showsFullPage.toggle()
                    }
                }
            }

            Group {
                
                switch phase {
                
                case .loading:
                    let title: LocalizedStringKey = pdfPreviewRequest.needsDownload ? "Downloading from iCloud…" : "Preparing Preview…"
                    ProgressView(title)
                    
                case .ready(let images):
                    let pageTop = showsFullPage ? nil : images.pageTop
                    Image(pageTop ?? images.fullPage, scale: 1, label: Text(pageTop == nil ? "First PDF page" : "Top of first PDF page"))
                        .resizable()
                        .scaledToFit()
                    
                case .failed(let error):
                    ContentUnavailableView {
                        Label("PDF Could Not Be Previewed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.userMessage)
                    }
                }
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .task {
            await loadPreview()
        }
    }

    private func loadPreview() async {
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
            
            phase = .ready(images)
        } catch {
            guard !Task.isCancelled else {
                return
            }

            phase = .failed(AppError(error))
        }
    }

    private nonisolated static func renderFirstPage(_ url: URL, _ syncFolder: URL?) throws -> PreviewImages {
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
                    return PreviewImages(fullPage: fullPage, pageTop: nil)
                }

                try Task.checkCancellation()

                let pageTop = try PDFContentService.render(page, 144, maximumHeightRatio: 1.15)

                return PreviewImages(fullPage: fullPage, pageTop: pageTop)
            }
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
