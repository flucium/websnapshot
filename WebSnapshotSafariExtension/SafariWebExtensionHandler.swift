import AppKit
import OSLog
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private static let logger = Logger(
        subsystem: "flucium.WebSnapshot.SafariExtension",
        category: "AppHandoff"
    )

    func beginRequest(with context: NSExtensionContext) {
        do {
            
            guard let item = context.inputItems.first as? NSExtensionItem,
                let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
                    throw SafariCaptureRequest.InvalidRequest.malformed
                }
            
            let request = try SafariCaptureRequest(message: message)
            
            guard let appURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "flucium.WebSnapshot"
            ) else {
                Self.logger.error("Launch Services could not locate WebSnapshot.")
                
                reply(context, error: "Open WebSnapshot once, then try the Safari button again.")
                
                return
            }
            
            let configuration = NSWorkspace.OpenConfiguration()
            
            configuration.activates = true
            
            NSWorkspace.shared.open([request.openURL], withApplicationAt: appURL, configuration: configuration) { _, error in
                if let error {
                
                    let nsError = error as NSError
                    
                    Self.logger.error("Opening WebSnapshot failed: domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .private)")
                }
                
                Self.complete(context, error: error == nil ? nil : "WebSnapshot could not be opened. Try opening the app first.")
            }
        } catch {
            reply(context, error: error.localizedDescription)
        }
    }

    private func reply(_ context: NSExtensionContext, error: String) {
        Self.complete(context, error: error)
    }

    private static func complete(_ context: NSExtensionContext, error: String?) {
        let response = NSExtensionItem()
        
        var message: [String: Any] = ["accepted": error == nil]
        
        if let error {
            message["error"] = error
        }
        
        response.userInfo = [SFExtensionMessageKey: message]
        
        context.completeRequest(returningItems: [response], completionHandler: nil)
    }
}
