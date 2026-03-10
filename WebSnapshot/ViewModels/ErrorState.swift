
//
//  ErrorState.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import Combine

@MainActor
final class ErrorState: ObservableObject {

    @Published var appError: AppError? = nil
    @Published var status: String = ""

    func setError(_ appError: AppError) {
        self.appError = appError
        status = appError.errorDescription ?? "unknown"
    }

    func setError(_ error: Error) {
        setError(AppError(error: error))
    }

    func clearError() {
        appError = nil
    }
}
