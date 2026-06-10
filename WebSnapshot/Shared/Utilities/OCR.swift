import Foundation
import CoreGraphics
import Vision

final class OCR {
    nonisolated static func recognizeText(_ image: CGImage, _ recognitionLanguages: [Locale.Language] = [] ) async throws -> String {
        
        var request = RecognizeTextRequest()
        
        request.recognitionLevel = .accurate
        
        request.automaticallyDetectsLanguage = recognitionLanguages.isEmpty
        
        request.recognitionLanguages = recognitionLanguages
        
        request.usesLanguageCorrection = true
        
        do{
            let observations = try await request.perform(on: image)

            return observations
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: "\n")
            
        }catch{
            throw AppError.textRecognitionFailed(error.localizedDescription)
        }
        
        

    }
}
