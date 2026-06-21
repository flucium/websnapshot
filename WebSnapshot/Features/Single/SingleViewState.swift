import SwiftUI
import Combine

@MainActor
final class SingleViewState : WebState{
    @Published var isFileExporterPresented = false
}

