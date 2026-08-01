import Foundation

struct AppError: Error, Equatable, Identifiable, LocalizedError, @unchecked Sendable {
    enum Kind: String, Equatable, Sendable {
        case generic
        case system
        case invalidLoad
        case invalidURL
        case network
        case io
        case invalidFileType
        case permissionDenied
        case notFound
        case timeout
        case translation
        case textRecognition
        case cancellation
    }

    let id: UUID
    let kind: Kind
    let userMessage: String
    let diagnosticMessage: String
    let underlyingError: NSError?
    let isRetryable: Bool

    var isCancellation: Bool {
        kind == .cancellation
    }

    var errorDescription: String? {
        userMessage
    }

    var recoverySuggestion: String? {
        switch kind {
        case .invalidURL:
            "Check the address and try again."
        case .invalidLoad:
            "Wait for the webpage to finish loading, then try again."
        case .network, .timeout:
            "Check your connection and try again."
        case .permissionDenied:
            "Choose the file again and allow WebSnapshot to access it."
        case .notFound:
            "Choose an existing file and try again."
        case .io:
            "Check the file location and try again."
        case .translation, .textRecognition:
            "Try again, or use a different page."
        case .generic, .system, .invalidFileType, .cancellation:
            nil
        }
    }

    static func == (_ lhs: AppError, _ rhs: AppError) -> Bool {
        lhs.id == rhs.id
    }

    init(_ error: Error) {
        if let appError = error as? AppError {
            self = appError
            return
        }

        let nsError = error as NSError

        if error is CancellationError ||
            (nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled) {
            self = .cancelled(error)
            return
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .timedOut:
                self = .timeout(
                    "The operation timed out.",
                    urlError.localizedDescription,
                    urlError
                )
            default:
                self = .invalidNetwork(
                    "A network error occurred.",
                    urlError.localizedDescription,
                    urlError
                )
            }
            return
        }

        if let cocoaError = error as? CocoaError {
            switch cocoaError.code {
            case .fileNoSuchFile:
                self = .notFound(
                    "The requested file could not be found.",
                    cocoaError.localizedDescription,
                    cocoaError
                )
            case .fileReadNoPermission, .fileWriteNoPermission:
                self = .permissionDenied(
                    "WebSnapshot does not have permission to access the file.",
                    cocoaError.localizedDescription,
                    cocoaError
                )
            default:
                self = .invalidIO(
                    "The file operation could not be completed.",
                    cocoaError.localizedDescription,
                    cocoaError
                )
            }
            return
        }

        self = .error(
            "The operation could not be completed.",
            error.localizedDescription,
            error
        )
    }

    static func presentable(_ error: Error) -> AppError? {
        let appError = AppError(error)
        return appError.isCancellation ? nil : appError
    }

    private init(
        _ kind: Kind,
        _ userMessage: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil,
        _ isRetryable: Bool
    ) {
        id = UUID()
        self.kind = kind
        self.userMessage = userMessage
        self.diagnosticMessage = diagnosticMessage ?? userMessage
        self.underlyingError = underlyingError.map { $0 as NSError }
        self.isRetryable = isRetryable
    }

    static func error(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .generic,
            message,
            diagnosticMessage,
            underlyingError,
            false
        )
    }

    static func system(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .system,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func invalidLoad(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .invalidLoad,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func invalidURL(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .invalidURL,
            message,
            diagnosticMessage,
            underlyingError,
            false
        )
    }

    static func invalidNetwork(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .network,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func invalidIO(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .io,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func invalidFileType(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .invalidFileType,
            message,
            diagnosticMessage,
            underlyingError,
            false
        )
    }

    static func permissionDenied(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .permissionDenied,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func notFound(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .notFound,
            message,
            diagnosticMessage,
            underlyingError,
            false
        )
    }

    static func timeout(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .timeout,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func translationFailed(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .translation,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func textRecognitionFailed(
        _ message: String,
        _ diagnosticMessage: String? = nil,
        _ underlyingError: Error? = nil
    ) -> AppError {
        AppError(
            .textRecognition,
            message,
            diagnosticMessage,
            underlyingError,
            true
        )
    }

    static func cancelled(_ underlyingError: Error? = nil) -> AppError {
        AppError(
            .cancellation,
            "The operation was cancelled.",
            nil,
            underlyingError,
            false
        )
    }
}
