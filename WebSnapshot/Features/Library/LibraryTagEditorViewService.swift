import Foundation
import SwiftData

@MainActor
final class LibraryTagEditorViewService {
    static func addNewTag(_ state: LibraryTagEditorViewState) {
        state.tagNames = PDFTagService.addingTag(state.newTagName,state.tagNames)

        state.newTagName = String()
    }

    static func removeTag(_ state: LibraryTagEditorViewState, _ name: String) {
        state.tagNames = PDFTagService.removingTag(name, state.tagNames)
    }

    static func save(_ state: LibraryTagEditorViewState, _ pdfFile: PDFFile, _ modelContext: ModelContext, sync: LibrarySyncService) -> Bool {
        
        do {
            try LibraryService.replaceTags(state.tagNames,pdfFile,modelContext, sync: sync)

            return true
        } catch {
            state.appError = AppError.presentable(error)

            return false
        }
        
    }
}
