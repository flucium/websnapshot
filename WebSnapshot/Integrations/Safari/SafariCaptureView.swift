import AppKit
import SwiftData
import SwiftUI
import WebKit

struct SafariCaptureView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @EnvironmentObject private var requests: SafariRequestService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if requests.current != nil {
                    ProgressView()
                        .controlSize(.small)
                }
    
                VStack(alignment: .leading, spacing: 4) {
                    
                    Text(requests.status)
                        .font(.headline)
                
                    if let url = requests.current?.url {
                        Text(url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !requests.pending.isEmpty {
                        Text("\(requests.pending.count) waiting")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                
                
                Spacer()
                
                if requests.current != nil || !requests.pending.isEmpty {
                    Button("Cancel", action: requests.cancel)
                }
                
                if let savedURL = requests.savedURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                    }
                }
            }
            .padding()

            if let error = requests.appError {
                
                VStack(alignment: .leading, spacing: 8) {
                    
                    Text(error.userMessage)
                    
                    HStack {
                        if requests.canRetry {
                            Button("Retry") {
                                requests.retry(modelContext)
                            }
                        }
                        
                        Button("Dismiss") {
                            requests.dismissError(modelContext)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            
            Divider()
            
            if let page = requests.webPage {
                WebView(page)
            } else {
                ContentUnavailableView("Save from Safari", systemImage: "safari", description: Text("Click the WebSnapshot button in Safari to save a webpage as PDF."))
            }
        }
        .frame(minWidth: 730, minHeight: 400)
        .onAppear {
            requests.startProcessing(modelContext)
        }
        .onChange(of: requests.pending.count) {
            requests.startProcessing(modelContext)
        }
        .onDisappear {
            requests.cancel()
        }
    }
}
