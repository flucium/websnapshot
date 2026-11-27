import SwiftData

@MainActor
final class SnapshotHistoryViewService {
    static func makeState(_ pdfFile: PDFFile, _ pdfFiles: [PDFFile]) -> SnapshotHistoryViewState {
        let versions = SnapshotHistoryService.versions(pdfFile, pdfFiles)

        return SnapshotHistoryViewState(versions: versions, selectedID: pdfFile.persistentModelID)
    }

    static func openVersion(_ libraryViewState: LibraryViewState, _ modelContext: ModelContext, _ pdfFile: PDFFile, _ librarySyncService: LibrarySyncService) {
        libraryViewState.showSnapshotHistory = false

        guard libraryViewState.selectedPDFFile?.persistentModelID != pdfFile.persistentModelID else {
            return
        }

        LibraryViewService.openPDF(libraryViewState, modelContext, pdfFile, librarySyncService)
    }
}
