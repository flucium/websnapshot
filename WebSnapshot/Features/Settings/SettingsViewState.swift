import Foundation
import Combine

final class SettingsViewState:ObservableObject{
    @Published var appError:AppError?
    @Published var appearance:AppearanceSettings.Appearance = .system
//    @Published var selectedTab:Int = 0
//    @Published var syncDirectoryIsValid:Bool = false
//    @Published var syncDirectory:String = String()
    
}
