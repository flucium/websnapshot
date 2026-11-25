import Foundation
import Combine
import CoreGraphics

@MainActor
final class PDFPreviewViewState:ObservableObject{
    nonisolated struct PreviewImages: Sendable {
        let fullPage: CGImage
        let pageTop: CGImage?
    }

    enum Phase {
        case loading
        case ready(PreviewImages)
        case failed(AppError)
    }

    @Published var phase: Phase = .loading

    @Published var showsFullPage = false
}

struct PDFPreviewRequest: Identifiable {
    let id = UUID()

    let fileName: String

    let url: Result<URL, AppError>

    let syncFolder: URL?

    let needsDownload: Bool
}
