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
    
    
    struct FileSource: Equatable {
        let id: PersistentIdentifier
        let url: URL
        let bookmarkData: Data?
        let syncRelativePath: String?

        init(_ pdfFile: PDFFile) {
            id = pdfFile.persistentModelID
            url = pdfFile.url
            bookmarkData = pdfFile.bookmarkData
            syncRelativePath = pdfFile.syncRelativePath
        }
    }

    struct FileLocation: Equatable {
        let source: FileSource
        let url: URL
        let availability: FileIO.Availability
    }
    
    
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

    

    
    @Published var appError:AppError?

    @Published var errorTitle = "Library Operation Could Not Be Completed"

    @Published var pendingDeletionPDFFile: PDFFile?

    @Published var showDeleteConfirmation = false
    
    @Published var searchText:String = String()
    
    @Published var selectedSearchMode: LibrarySearchMode = .all

    @Published var selectedTag: TagSelection = .all

    @Published var selectedPDFRowID: PersistentIdentifier?

    @Published var downloadingPDFs: Set<PersistentIdentifier> = []

    @Published private(set) var fileLocations: [PersistentIdentifier: FileLocation] = [:]

    @Published private(set) var displayedPDFData: Data?

    @Published private(set) var displayedPDFVersion = UUID()
    
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
    
    @Published var currentPageIndex = 0 {
        didSet {
            if oldValue != currentPageIndex, isTranslating || isTranslationPresented {
                cancelTranslation()
            }
        }
    }
    
    private(set) var displayedPDFURL: URL?

    private(set) var displayedPDFFingerprint: String?

    private var openRequestID: UUID?

    var openPDFTask: Task<Void, Never>?
    
    let libraryTagEditorViewState = LibraryTagEditorViewState()
    
    var translationPreparationTask: Task<Void, Never>?
    

    func beginTranslation(_ pdfFile: PDFFile, _ translationLanguage: TranslationLanguage) -> TranslationRequest {
        cancelTranslation()
        
        let request = TranslationRequest( pdfFileID: pdfFile.persistentModelID, url: pdfFile.resolvedURL, pageIndex: currentPageIndex, data: displayedPDFData, version: displayedPDFVersion, configuration: TranslationSession.Configuration(source: translationLanguage.opposite.localeLanguage, target: translationLanguage.localeLanguage, preferredStrategy: .lowLatency ) )
        
        translationRequest = request
        
        isTranslating = true
        
        return request
    }

    func isCurrentTranslation(_ translationRequest: TranslationRequest) -> Bool {
        
        self.translationRequest?.id == translationRequest.id && selectedPDFFile?.persistentModelID == translationRequest.pdfFileID && displayedPDFVersion == translationRequest.version
        
    }

    func prepareTranslation(_ text: String,  for  translationRequest: TranslationRequest) {
        
        guard isCurrentTranslation(translationRequest) else {
            return
        }
        
        var prepared = translationRequest
        
        prepared.text = text
        
        self.translationRequest = prepared
    }

    func completeTranslation(_ text: String, for translationRequest: TranslationRequest) {
        
        guard isCurrentTranslation(translationRequest) else {
            return
        }
        
        translatedText = text
        
        isTranslationPresented = true
        
        finishTranslation(translationRequest)
    }

    func finishTranslation(_ translationRequest: TranslationRequest) {
        
        guard isCurrentTranslation(translationRequest) else {
            return
        }
        
        self.translationRequest = nil
        
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

    func updateFileLocations(_ fileLocations: [PersistentIdentifier: FileLocation]) {
        if self.fileLocations != fileLocations {
            self.fileLocations = fileLocations
        }
    }

    func fileURL(_ pdfFile: PDFFile) -> URL {
        fileLocation(pdfFile)?.url ?? pdfFile.url
    }

    func fileAvailability(_ pdfFile: PDFFile) -> FileIO.Availability {
        fileLocation(pdfFile)?.availability ?? .unavailable
    }

    private func fileLocation(_ pdfFile: PDFFile) -> FileLocation? {
        guard let fileLocation = fileLocations[pdfFile.persistentModelID], fileLocation.source == FileSource(pdfFile) else {
            return nil
        }

        return fileLocation
    }
    

    func closeTagEditor() {
    
        tagEditorPDFFile = nil
        
        libraryTagEditorViewState.clear()
    }
    
}
