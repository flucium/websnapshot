import Foundation
import Combine

@MainActor
final class LibraryTagEditorViewState:ObservableObject{
    @Published var tagNames: [String] = []

    @Published var newTagName = String()

    @Published var appError: AppError?

    func prepare(_ pdfFile: PDFFile) {
        tagNames = PDFTagService.tagNames(pdfFile.tags)

        newTagName = String()

        appError = nil
    }

    func clear() {
        tagNames = []

        newTagName = String()

        appError = nil
    }
}
