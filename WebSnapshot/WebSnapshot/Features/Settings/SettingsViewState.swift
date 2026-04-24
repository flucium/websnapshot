import Foundation
import Combine

@MainActor
final class SettingsViewState: ObservableObject {
    @Published var error: AppError?
}
