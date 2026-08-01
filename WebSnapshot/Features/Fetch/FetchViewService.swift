import Foundation
import WebKit

final class FetchViewService{
    static func fetch(_ input: String) async throws -> WebPage {
        guard let url = URL.supportedWebURL(input) else {
            throw AppError.invalidURL("Enter a valid HTTP or HTTPS address.")
        }

        do {
            return try await WebService.fetch(url)
        } catch let error as CancellationError {
            throw error
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError.invalidLoad(
                "The webpage could not be loaded.",
                error.localizedDescription,
                error
            )
        }
    }
}
