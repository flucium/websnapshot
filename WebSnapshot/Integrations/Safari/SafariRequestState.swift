import Foundation
import WebKit

@MainActor
struct SafariRequestState {
    var pending: [SafariCaptureRequest] = []

    var current: SafariCaptureRequest?

    var webPage: WebPage?

    var savedURL: URL?

    var status = "Ready to save from Safari."

    var appError: AppError?
}
