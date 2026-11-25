import SwiftUI

struct PDFPreviewView: View {

    @StateObject private var pdfPreviewViewState = PDFPreviewViewState()

    private let pdfPreviewRequest: PDFPreviewRequest

    static let windowID = "pdf-preview"
    

    init(_ pdfPreviewRequest: PDFPreviewRequest) {
        self.pdfPreviewRequest = pdfPreviewRequest
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                
                Text(pdfPreviewRequest.fileName)
                    .font(.headline)
                    .lineLimit(1)

                if case .ready(let images) = pdfPreviewViewState.phase, images.pageTop != nil {
                    Spacer(minLength: 8)

                    Button(pdfPreviewViewState.showsFullPage ? "Show Page Top" : "Show Full Page") {
                        pdfPreviewViewState.showsFullPage.toggle()
                    }
                }
            }

            Group {
                
                switch pdfPreviewViewState.phase {
                
                case .loading:
                    let title: LocalizedStringKey = pdfPreviewRequest.needsDownload ? "Downloading from iCloud…" : "Preparing Preview…"
                    ProgressView(title)
                    
                case .ready(let images):
                    let pageTop = pdfPreviewViewState.showsFullPage ? nil : images.pageTop
                    Image(pageTop ?? images.fullPage, scale: 1, label: Text(pageTop == nil ? "First PDF page" : "Top of first PDF page"))
                        .resizable()
                        .scaledToFit()
                    
                case .failed(let error):
                    ContentUnavailableView {
                        Label("PDF Could Not Be Previewed", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(error.userMessage)
                    }
                }
                
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(12)
        .task {
            await PDFPreviewViewService.loadPreview(pdfPreviewViewState, pdfPreviewRequest)
        }
    }
}
