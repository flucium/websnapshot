import Combine
import WebKit

@MainActor
class WebState: ObservableObject {
    @Published var appError: AppError?
    @Published var webPage = WebPage()
    @Published var searchText: String = String()
    
    func clear() {
        self.appError = nil
        self.webPage = WebPage()
        self.searchText = String()
    }
}
