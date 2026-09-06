import Foundation
import Combine

final class SettingsViewState:ObservableObject{
    @Published var appError:AppError?
    @Published var errorTitle = "Setting Could Not Be Saved"
    
}
