import Foundation
import Combine
import Translation
import SwiftData

@MainActor
final class LibraryViewState:ObservableObject{

    enum TagSelection: Hashable {
        case all
        case untagged
        case tag(String)
    }
    
    @Published var appError:AppError?

    @Published var errorTitle = "Library Operation Could Not Be Completed"

    @Published var currentPageIndex = 0
    
    @Published var searchText:String = String()
    
    @Published var selectedSearchMode: LibrarySearchMode = .all

    @Published var selectedTag: TagSelection = .all

    @Published var selectedPDFRowID: PersistentIdentifier?

    @Published var downloadingPDFs: Set<PersistentIdentifier> = []

    @Published private(set) var displayedPDFData: Data?

    @Published private(set) var displayedPDFVersion = UUID()

    private(set) var displayedPDFURL: URL?

    private(set) var displayedPDFFingerprint: String?

    private var openRequestID: UUID?

    var openPDFTask: Task<Void, Never>?
    
    @Published var tagEditorPDFFile: PDFFile?
    
    
    @Published  var translatedText = String()
    
    @Published  var isTranslating = false
    
    @Published  var isTranslationPresented = false
    
    @Published private(set) var translationRequest: TranslationRequest?
    
    @Published var selectedPDFFile: PDFFile? {
        didSet {
            if oldValue?.persistentModelID != selectedPDFFile?.persistentModelID {
                cancelOpeningPDF()
                cancelTranslation()
                currentPageIndex = 0
                displayedPDFData = nil
                displayedPDFURL = nil
                displayedPDFFingerprint = nil
                displayedPDFVersion = UUID()
            }
        }
    }
    
    
    let libraryTagEditorViewState = LibraryTagEditorViewState()
    
    var translationPreparationTask: Task<Void, Never>?
    
    struct TranslationRequest: Identifiable {
        let id = UUID()
        let pdfFileID: PersistentIdentifier
        let url: URL
        let pageIndex: Int
        let data: Data?
        let version: UUID
        let configuration: TranslationSession.Configuration
        var text: String?
    }

    

    func beginTranslation(_ pdfFile: PDFFile, _ language: TranslationLanguage) -> TranslationRequest {
        cancelTranslation()
        
        let request = TranslationRequest( pdfFileID: pdfFile.persistentModelID, url: pdfFile.resolvedURL, pageIndex: currentPageIndex, data: displayedPDFData, version: displayedPDFVersion, configuration: TranslationSession.Configuration(source: language.opposite.localeLanguage, target: language.localeLanguage, preferredStrategy: .lowLatency ) )
        
        translationRequest = request
        
        isTranslating = true
        
        return request
    }

    func isCurrentTranslation(_ request: TranslationRequest) -> Bool {
        
        translationRequest?.id == request.id && selectedPDFFile?.persistentModelID == request.pdfFileID && displayedPDFVersion == request.version
        
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

    func beginOpeningPDF() -> UUID {
        cancelOpeningPDF()

        let request = UUID()

        openRequestID = request

        return request
    }

    func isCurrentOpenRequest(_ request: UUID) -> Bool {
        openRequestID == request
    }

    func completeOpeningPDF(_ pdfFile: PDFFile, for request: UUID) {
        guard isCurrentOpenRequest(request) else {
            return
        }

        finishOpeningPDF(request)

        selectedPDFRowID = pdfFile.persistentModelID

        selectedPDFFile = pdfFile
    }

    func finishOpeningPDF(_ request: UUID) {
        guard isCurrentOpenRequest(request) else {
            return
        }

        openRequestID = nil

        openPDFTask = nil

        downloadingPDFs.removeAll()
    }

    func cancelOpeningPDF() {
        openRequestID = nil

        openPDFTask?.cancel()

        openPDFTask = nil

        downloadingPDFs.removeAll()
    }

    func displayPDF(_ data: Data, _ url: URL, _ fingerprint: String) {
        guard selectedPDFFile?.resolvedURL == url else {
            return
        }

        guard displayedPDFURL != url || displayedPDFFingerprint != fingerprint else {
            return
        }

        cancelTranslation()

        displayedPDFURL = url

        displayedPDFFingerprint = fingerprint

        displayedPDFData = data

        displayedPDFVersion = UUID()
    }

    func presentTagEditor(_ pdfFile: PDFFile) {
    
        libraryTagEditorViewState.prepare(pdfFile)
        
        tagEditorPDFFile = pdfFile
    }
    

    func closeTagEditor() {
    
        tagEditorPDFFile = nil
        
        libraryTagEditorViewState.clear()
    }
    
}
