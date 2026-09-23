import Foundation
import Combine
import Translation
import SwiftData

@MainActor
final class LibraryViewState:ObservableObject{
    
    var translationPreparationTask: Task<Void, Never>?
    
    @Published var appError:AppError?
    
    @Published var errorTitle = "Library Operation Could Not Be Completed"
    
    @Published var searchText:String = String()
    
    @Published var selectedSearchMode: SearchMode = .all
    
    @Published var tagEditorPDFFile: PDFFile?
    
    @Published var tagEditorTagNames: [String] = []
    
    @Published var tagEditorNewTagName = String()
    
    @Published var tagEditorAppError: AppError?
    
    @Published  var currentPageIndex = 0
    
    @Published  var translatedText = String()
    
    @Published  var isTranslating = false
    
    @Published  var isTranslationPresented = false
    
    @Published private(set) var translationRequest: TranslationRequest?
    
    @Published var selectedPDFFile: PDFFile? {
        didSet {
            if oldValue?.persistentModelID != selectedPDFFile?.persistentModelID {
                cancelTranslation()
                currentPageIndex = 0
            }
        }
    }
    
    
    struct TranslationRequest: Identifiable {
        let id = UUID()
        let pdfFileID: PersistentIdentifier
        let url: URL
        let pageIndex: Int
        let configuration: TranslationSession.Configuration
        var text: String?
    }

    

    func beginTranslation(_ pdfFile: PDFFile, _ language: TranslationLanguage) -> TranslationRequest {
        cancelTranslation()
        
        let request = TranslationRequest( pdfFileID: pdfFile.persistentModelID, url: pdfFile.resolvedURL, pageIndex: currentPageIndex, configuration: TranslationSession.Configuration(source: language.opposite.localeLanguage, target: language.localeLanguage, preferredStrategy: .lowLatency ) )
        
        translationRequest = request
        
        isTranslating = true
        
        return request
    }

    func isCurrentTranslation(_ request: TranslationRequest) -> Bool {
        
        translationRequest?.id == request.id && selectedPDFFile?.persistentModelID == request.pdfFileID
        
    }

    func prepareTranslation(_ text: String,  for  request: TranslationRequest) {
        
        guard isCurrentTranslation(request) else {
            return
        }
        
        var prepared = request
        
        prepared.text = text
        
        translationRequest = prepared
    }

    func completeTranslation(_ text: String, for request: TranslationRequest) {
        
        guard isCurrentTranslation(request) else {
            return
        }
        
        translatedText = text
        
        isTranslationPresented = true
        
        finishTranslation(request)
    }

    func finishTranslation(_ request: TranslationRequest) {
        
        guard isCurrentTranslation(request) else {
            return
        }
        
        translationRequest = nil
        
        translationPreparationTask = nil
        
        isTranslating = false
    }

    func cancelTranslation() {
        
        translationPreparationTask?.cancel()
        
        translationPreparationTask = nil
        
        translationRequest = nil
        
        isTranslating = false
        
        isTranslationPresented = false
        
        translatedText = String()
    }

    func presentTagEditor(_ pdfFile: PDFFile) {
    
        tagEditorTagNames = PDFTagService.tagNames(pdfFile.tags)
        
        tagEditorNewTagName = String()
        
        tagEditorAppError = nil
        
        tagEditorPDFFile = pdfFile
    }
    

    func closeTagEditor() {
    
        tagEditorPDFFile = nil
        
        tagEditorTagNames = []
        
        tagEditorNewTagName = String()
        
        tagEditorAppError = nil
    }
    
}
