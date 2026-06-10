import Combine
import WebKit

@MainActor
class WebState: ObservableObject {
    @Published var appError: AppError?
    @Published var webPage = WebPage()
    @Published var pdfFileDocument: PDFFileDocument?
    @Published var searchText: String = String()
    
    func clear() {
        self.appError = nil
        self.webPage = WebPage()
        self.pdfFileDocument = nil
        self.searchText = String()
    }
}
