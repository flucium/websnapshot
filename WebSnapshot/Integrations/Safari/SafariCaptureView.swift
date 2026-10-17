import AppKit
import SwiftData
import SwiftUI
import WebKit

struct SafariCaptureView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @ObservedObject private var requests: SafariRequestService

    private var requestState: SafariRequestState { requests.state }

    init(_ requests: SafariRequestService) {
        self.requests = requests
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if requestState.current != nil {
                    ProgressView()
                        .controlSize(.small)
                }
    
                VStack(alignment: .leading, spacing: 4) {
                    
                    Text(requestState.status)
                        .font(.headline)
                
                    if let url = requestState.current?.url {
                        Text(url.absoluteString)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    
                    if !requestState.pending.isEmpty {
                        Text("\(requestState.pending.count) waiting")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                
                
                Spacer()
                
                if requestState.current != nil || !requestState.pending.isEmpty {
                    Button("Cancel", action: requests.cancel)
                }
                
                if let savedURL = requestState.savedURL {
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([savedURL])
                    }
                }
            }
            .padding()

            if let error = requestState.appError {
                
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
            
            if let page = requestState.webPage {
                WebView(page)
            } else {
                ContentUnavailableView("Save from Safari", systemImage: "safari", description: Text("Click the WebSnapshot button in Safari to save a webpage as PDF."))
            }
        }
        .frame(minWidth: 730, minHeight: 400)
        .onAppear {
            requests.startProcessing(modelContext)
        }
        .onChange(of: requestState.pending.count) {
            requests.startProcessing(modelContext)
        }
        .onDisappear {
            requests.cancel()
        }
    }
}
