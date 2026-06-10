import Foundation
import Combine
import Translation

final class DirectoryViewState:ObservableObject{
    @Published var appError:AppError?
    @Published var searchText:String = String()
    @Published var selectedPDFFile: PDFFile?
    @Published  var currentPageIndex = 0
    @Published  var textToTranslate = String()
    @Published  var translatedText = String()
    @Published  var translationConfiguration: TranslationSession.Configuration?
    @Published  var isTranslating = false
    @Published  var isTranslationPresented = false
}
