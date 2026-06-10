import Foundation

enum AppError: Error, Equatable,Identifiable {
    
    var id: String {
        switch self {
            
        case .error:
            "Error: \(self.localizedDescription)"
            
        case .system:
            "System: \(self.localizedDescription)"
            
        case .invalidLoad:
            "Invalid load: \(self.localizedDescription)"
            
        case .invalidURL:
            "Not invalid url: \(self.localizedDescription)"
            
        case .invalidNetwork:
            "Invalid network: \(self.localizedDescription)"
            
        case .invalidIO:
            "Invalid io: \(self.localizedDescription)"
            
        case .invalidFileType:
            "Invalid file type: \(self.localizedDescription)"
            
        case .permissionDenied:
            "Permission denied: \(self.localizedDescription)"
            
        case .notFound:
            "Not found: \(self.localizedDescription)"
            
            
        case .timeout:
            "Timeout: \(self.localizedDescription)"
            
        case .alreadyExists:
            "Already exists: \(self.localizedDescription)"
            
        case .translationFailed:
            "Translation failed: \(self.localizedDescription)"
        
        case .textRecognitionFailed:
            "Text recognition failed: \(self.localizedDescription)"
            
        }
        
        
        
    }
    
    
    case error(_ message:String)
    case system(_ message:String)
    case invalidLoad(_ message:String)
    case invalidURL(_ message:String)
    case invalidNetwork(_ message:String)
    case invalidIO(_ message:String)
    case invalidFileType(_ message:String)
    case permissionDenied(_ message:String)
    case notFound(_ message:String)
    case timeout(_ message:String)
    case alreadyExists(_ message:String)
    case translationFailed(_ message:String)
    case textRecognitionFailed(_ message:String)
}

extension AppError{
    init(_ error: Error) {
           if let appError = error as? AppError {
               self = appError
               return
           }

    
        if let cocoaError = error as? CocoaError {
            switch cocoaError.code {
            case .fileNoSuchFile:
                self = .error(
                    cocoaError.localizedDescription
                )
            default:
                self = .error(
                    cocoaError.localizedDescription
                )
            }
            return
        }
        
        self = .error(error.localizedDescription)
    }
}
