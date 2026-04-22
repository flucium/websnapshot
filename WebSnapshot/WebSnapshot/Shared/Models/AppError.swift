import Foundation


enum AppError: Error, Equatable {
    case notImplemented
    case todo
    case unknown(message: String)
    case debug(debugMessage: String? = nil)
    case display(message: String)
    case invalidURL
    case invalidFileType
    case permissionDenied
    case notFound
}

extension AppError {
    init(_ error: Error) {
        if let appError = error as? AppError {
            self = appError
            return
        }

        if let urlError = error as? URLError {
            switch urlError.code {
            case .badURL, .unsupportedURL:
                self = .invalidURL
            case .fileDoesNotExist:
                self = .notFound
            case .noPermissionsToReadFile:
                self = .permissionDenied
            default:
                self = .unknown(message: urlError.localizedDescription)
            }
            return
        }

        if let cocoaError = error as? CocoaError {
            switch cocoaError.code {
            case .fileNoSuchFile:
                self = .notFound
            case .fileReadNoPermission, .fileWriteNoPermission:
                self = .permissionDenied
            default:
                self = .unknown(message: cocoaError.localizedDescription)
            }
            return
        }

        self = .unknown(message: error.localizedDescription)
    }

    static func from(
        _ message: String,
    ) -> AppError {
        .display(
            message: message,
        )
    }

}

extension AppError: LocalizedError {
    var errorDescription: String? {
        switch self {

        case .todo:
            return "Todo"

        case .notImplemented:
            return "Not implemented"

        case .debug(let debugMessage):
            return debugMessage

        case .unknown(let message):
            return message

        case .display(let message):
            return message

        case .invalidURL:
            return "InvalidURL"
        case .invalidFileType:
            return "Invalid file type"
            
        case .permissionDenied:
            return "Permission denied"
            
        case .notFound:
            return "Not found"

        }
    }

}
