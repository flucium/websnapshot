import Combine
import Foundation
import WebKit

@MainActor
final class SafariRequestState: ObservableObject {
    @Published var pending: [SafariCaptureRequest] = []

    @Published var current: SafariCaptureRequest?

    @Published var webPage: WebPage?

    @Published var savedURL: URL?

    @Published var status = "Ready to save from Safari."

    @Published var appError: AppError?
}
