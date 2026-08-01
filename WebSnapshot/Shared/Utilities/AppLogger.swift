import Foundation
import OSLog

enum AppLogger {
    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "WebSnapshot",
        category: "Error"
    )

    static func record(
        _ error: AppError,
        _ operation: String,
        _ targetURL: URL? = nil
    ) {
        guard error.isCancellation == false else {
            return
        }

        let underlyingDomain = error.underlyingError?.domain ?? "none"
        let underlyingCode = error.underlyingError?.code ?? 0
        let target = targetURL?.path ?? "none"

        logger.error(
            "operation=\(operation, privacy: .public) category=\(error.kind.rawValue, privacy: .public) retryable=\(error.isRetryable, privacy: .public) underlyingDomain=\(underlyingDomain, privacy: .public) underlyingCode=\(underlyingCode, privacy: .public) diagnostic=\(error.diagnosticMessage, privacy: .private) target=\(target, privacy: .private(mask: .hash))"
        )
    }

    static func recordDiagnostic(
        _ message: String,
        _ operation: String,
        _ targetURL: URL? = nil
    ) {
        let target = targetURL?.path ?? "none"

        logger.notice(
            "operation=\(operation, privacy: .public) diagnostic=\(message, privacy: .private) target=\(target, privacy: .private(mask: .hash))"
        )
    }
}
