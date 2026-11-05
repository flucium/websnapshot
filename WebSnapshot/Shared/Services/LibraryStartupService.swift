import Combine
import Foundation
import SwiftData

@MainActor
final class LibraryStartupService: ObservableObject {
    enum State {
        case idle
        case opening
        case ready(ModelContainer)
        case failed(AppError)
    }

    @Published private(set) var state: State = .idle

    private let createContainer: CreateContainer

    typealias CreateContainer = @MainActor () throws -> ModelContainer

    var modelContainer: ModelContainer? {
        guard case .ready(let container) = state else {
            return nil
        }

        return container
    }

    init(_ createContainer: @escaping CreateContainer = {
        try ModelContainer(for: AppearanceSettings.self, StorageSettings.self, PDFFile.self, PDFTag.self, configurations: ModelConfiguration(cloudKitDatabase: .none))
    }) {
        self.createContainer = createContainer
    }

    func open() async {
        switch state {
        case .opening, .ready:
            return
        case .idle, .failed:
            break
        }

        state = .opening

        await Task.yield()

        do {
            try Task.checkCancellation()

            let container = try createContainer()

            state = .ready(container)
        } catch {
            
            let diagnostic = "\(String(reflecting: error))\n\(String(reflecting: error as NSError))"

            let appError = AppError.system("The WebSnapshot library could not be opened.", diagnostic, error)

            AppLogger.record(appError, "Open WebSnapshot library")

            state = .failed(appError)
        }
    }
}
