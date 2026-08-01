import SwiftUI

final class AlertModal{
    static func show(
        _ title: String,
        _ error: AppError,
        _ retryAction: (() -> Void)? = nil
    ) -> Alert {
        let message = [error.userMessage, error.recoverySuggestion]
            .compactMap { $0 }
            .joined(separator: "\n\n")

        if error.isRetryable, let retryAction {
            return Alert(
                title: Text(title),
                message: Text(message),
                primaryButton: .default(Text("Try Again"), action: retryAction),
                secondaryButton: .cancel()
            )
        }

        return Alert(
            title: Text(title),
            message: Text(message),
            dismissButton: .default(Text("OK"))
        )
    }
}
