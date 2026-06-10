import Foundation
import Translation

enum TranslationLanguage {
    case english
    case japanese

    var opposite: TranslationLanguage {
        switch self {
        case .english:
            .japanese
        case .japanese:
            .english
        }
    }

    var localeLanguage: Locale.Language {
        switch self {
        case .english:
            Locale.Language(identifier: "en")
        case .japanese:
            Locale.Language(identifier: "ja")
        }
    }
}

@available(visionOS, unavailable)
final class Translation {
    static func translate(_ fromLanguage: TranslationLanguage, _ toLanguage: TranslationLanguage, _ text: String) async throws -> String {
        
        guard text.isEmpty == false else {
            return String()
        }

        let session = TranslationSession(
            installedSource: fromLanguage.localeLanguage,
            target: toLanguage.localeLanguage,
            preferredStrategy: .lowLatency
        )
        
        do{
            return try await translate(using: session, text)
        }catch{
            throw AppError.translationFailed(error.localizedDescription)
        }
    }

    static func translate(using session: TranslationSession, _ text: String) async throws -> String {
        guard text.isEmpty == false else {
            return ""
        }

        do{
            let response = try await session.translate(text)
            
            return response.targetText
        }catch{
            throw AppError.translationFailed(error.localizedDescription)
        }
    }
}
