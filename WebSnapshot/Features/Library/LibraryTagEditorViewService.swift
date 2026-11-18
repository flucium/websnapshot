import Foundation
import SwiftData

@MainActor
final class LibraryTagEditorViewService {
    static func addNewTag(_ libraryTagEditorViewState: LibraryTagEditorViewState) {
        libraryTagEditorViewState.tagNames = PDFTagService.addingTag(libraryTagEditorViewState.newTagName,libraryTagEditorViewState.tagNames)

        libraryTagEditorViewState.newTagName = String()
    }

    static func removeTag(_ libraryTagEditorViewState: LibraryTagEditorViewState, _ name: String) {
        libraryTagEditorViewState.tagNames = PDFTagService.removingTag(name, libraryTagEditorViewState.tagNames)
    }

    static func save(_ libraryTagEditorViewState: LibraryTagEditorViewState, _ pdfFile: PDFFile, _ modelContext: ModelContext, _ librarySyncService: LibrarySyncService) -> Bool {
        
        do {
            let names = PDFTagService.mergingTagChanges(libraryTagEditorViewState.tagNames, previous: libraryTagEditorViewState.originalTagNames, current: PDFTagService.tagNames(pdfFile.tags))

            try LibraryService.replaceTags(names,pdfFile,modelContext, librarySyncService)

            return true
        } catch {
            libraryTagEditorViewState.appError = AppError.presentable(error)

            return false
        }
        
    }
}
