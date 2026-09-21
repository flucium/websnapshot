import AppKit
import SafariServices

final class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    func beginRequest(with context: NSExtensionContext) {
        do {
            
            guard let item = context.inputItems.first as? NSExtensionItem,
                let message = item.userInfo?[SFExtensionMessageKey] as? [String: Any] else {
                    throw SafariCaptureRequest.InvalidRequest.malformed
                }
            
            let request = try SafariCaptureRequest(message: message)
            
            let appURL = Bundle.main.bundleURL.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            
            guard appURL.pathExtension == "app", Bundle(url: appURL)?.bundleIdentifier == "flucium.WebSnapshot" else {
                    reply(context, error: "Reinstall WebSnapshot to restore its Safari extension.")
                    return
                }
            
            let configuration = NSWorkspace.OpenConfiguration()
            
            configuration.activates = true
            
            NSWorkspace.shared.open([request.openURL], withApplicationAt: appURL, configuration: configuration) { _, error in Self.complete(context, error: error == nil ? nil : "WebSnapshot could not be opened. Try opening the app first.")
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
