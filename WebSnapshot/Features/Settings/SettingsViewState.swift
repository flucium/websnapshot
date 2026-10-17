import Foundation
import Combine

@MainActor
final class SettingsViewState:ObservableObject{
    @Published var appError:AppError?
    @Published var errorTitle = "Setting Could Not Be Saved"
    @Published var selectedAppearance: AppearanceSettings.Appearance = .system
    @Published var selectedStorage: StorageSettings.Storage = .flexibility
    @Published var selectedSync = false
    
}
