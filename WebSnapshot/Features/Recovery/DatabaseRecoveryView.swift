import AppKit
import SwiftUI

struct DatabaseRecoveryView: View {
    @ObservedObject var libraryStartupService: LibraryStartupService

    let retry: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            if case .failed(let error) = libraryStartupService.state {
                recovery(error)
            } else {
                ProgressView("Opening Library…")
            }
        }
        .frame(maxWidth: 560)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
    }

    private func recovery(_ error: AppError) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 34))
                    .foregroundStyle(.orange)
                    .accessibilityHidden(true)

                Text("Library Could Not Be Opened")
                    .font(.title2.weight(.semibold))
            }

            Text(error.userMessage)

            Text("Retry opens the existing library. Your saved PDFs will not be deleted.")
                .font(.callout)
                .foregroundStyle(.secondary)

            DisclosureGroup("Error Details") {
                ScrollView {
                    Text(error.diagnosticMessage)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 120)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }

            HStack(spacing: 10) {
                Button("Quit WebSnapshot") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Copy Error Details") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(error.diagnosticMessage, forType: .string)
                }

                Button("Try Again", action: retry)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}
