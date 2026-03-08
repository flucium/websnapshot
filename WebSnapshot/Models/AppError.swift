//
//  AppError.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/09.
//

import Foundation

enum AppError: Error, Equatable {
    case notImplemented
    case todo
    case unknown(message: String)
    case debug(debugMessage: String? = nil)
    case display(message: String)
    case invalidURL
    case permissionDenied
}

extension AppError {
    init(error: Error) {
        if let appError = error as? AppError {
            self = appError
            return
        }

        self = .notImplemented
    }

    static func from(
        message: String,
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
            return "todo"

        case .notImplemented:
            return "not implemented"

        case .debug(let debugMessage):
            return debugMessage

        case .unknown(let message):
            return message

        case .display(let message):
            return message

        case .invalidURL:
            return "invalid url"

        case .permissionDenied:
            return "permission denied"

        }
    }

}
