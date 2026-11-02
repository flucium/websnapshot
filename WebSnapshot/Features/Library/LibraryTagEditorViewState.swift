import Foundation
import Combine

@MainActor
final class LibraryTagEditorViewState:ObservableObject{
    @Published var tagNames: [String] = []

    @Published var newTagName = String()

    @Published var appError: AppError?

    private(set) var originalTagNames: [String] = []

    func prepare(_ pdfFile: PDFFile) {
        tagNames = PDFTagService.tagNames(pdfFile.tags)

        originalTagNames = tagNames

        newTagName = String()

        appError = nil
    }

    func clear() {
        tagNames = []

        originalTagNames = []

        newTagName = String()

        appError = nil
    }
}
