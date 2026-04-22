import Foundation
import Combine

@MainActor
final class DirectoryViewState: ObservableObject {
    @Published var error: AppError?
    @Published var searchText: String = String()
}
