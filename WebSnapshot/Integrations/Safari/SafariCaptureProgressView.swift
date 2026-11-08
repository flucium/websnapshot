import AppKit
import SwiftUI

struct SafariCaptureProgressView: View {
    @ObservedObject var safariRequests: SafariRequestService

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Saving Webpage")
                .font(.title2.weight(.semibold))

            if let request = safariRequests.state.current {
                Text(request.url.absoluteString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .help(request.url.absoluteString)
            }

            HStack(spacing: 12) {
                ProgressView().controlSize(.small)

                VStack(alignment: .leading, spacing: 4) {
                    Text(safariRequests.state.isCancelling ? "Cancelling…" : safariRequests.state.status)
                        .font(.callout.weight(.medium))

                    if let progress = safariRequests.state.exportState {
                        Text(progress.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if !safariRequests.state.pending.isEmpty {
                Text(safariRequests.state.pending.count == 1 ? "1 more webpage queued" : "\(safariRequests.state.pending.count) more webpages queued")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Spacer()

                Button(safariRequests.state.pending.isEmpty ? "Cancel" : "Cancel All") {
                    safariRequests.cancel()
                }
                .keyboardShortcut(.cancelAction)
                .disabled(safariRequests.state.isCancelling)
                .help("Cancel the current save and all queued requests.")
            }
        }
        .padding(24)
        .frame(width: 480)
        .background(.background)
    }
}

@MainActor
final class SafariCaptureProgressWindow: NSWindowController, NSWindowDelegate {
    private let safariRequests: SafariRequestService

    private var hiddenRequestID: UUID?

    init(_ safariRequests: SafariRequestService) {
        self.safariRequests = safariRequests

        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 480, height: 280), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        
        panel.title = "Saving Webpages"
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.contentView = NSHostingView(rootView: SafariCaptureProgressView(safariRequests: safariRequests))

        super.init(window: panel)

        panel.delegate = self
        panel.center()
    }

    required init?(coder: NSCoder) {
        return nil
    }

    func update() {
        guard let request = safariRequests.state.current, safariRequests.state.appError == nil else {
            window?.orderOut(nil)
            return
        }

        guard request.id != hiddenRequestID, window?.isVisible != true else {
            return
        }

        prepareForSafariDialog()
        showWindow(nil)
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        hiddenRequestID = safariRequests.state.current?.id
        safariRequests.cancel()
        return true
    }
}
