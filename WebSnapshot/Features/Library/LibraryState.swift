import Foundation
import Combine

@MainActor
class LibraryState:ObservableObject{
    @Published var appError:AppError?

    @Published var errorTitle = "Library Operation Could Not Be Completed"

    @Published var currentPageIndex = 0
}
