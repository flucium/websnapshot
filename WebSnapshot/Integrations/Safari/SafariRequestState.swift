import Foundation
import WebKit

@MainActor
struct SafariRequestState {
    var pending: [SafariCaptureRequest] = []

    var current: SafariCaptureRequest?

    var webPage: WebPage?

    var savedURL: URL?

    var status = "Ready to reload a URL from Safari without its sign-in or form entries."

    var appError: AppError?
}
