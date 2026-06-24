import SwiftUI
import SwiftData
import Translation
import AppKit

struct LibraryView:View {

    @Environment(\.modelContext) private var modelContext

    @Query private var pdfFiles: [PDFFile]

    @StateObject private var libraryViewState = LibraryViewState()

    
    var body: some View {
        VStack{
            
            if libraryViewState.selectedPDFFile == nil{
                searchTextFieldView()

                pdfListView()
            }else{
                pdfView()
            }
        }
        .translationTask(libraryViewState.translationConfiguration) { session in
            guard libraryViewState.textToTranslate.isEmpty == false else {
                libraryViewState.isTranslating = false
                return
            }

            do {
                libraryViewState.translatedText = try await Translation.translate(using: session,libraryViewState.textToTranslate)

                libraryViewState.isTranslationPresented = true
            } catch {
                libraryViewState.appError = AppError(error)
            }

            libraryViewState.isTranslating = false
        }
        .alert(
            item: $libraryViewState.appError
        ) { appError in
            AlertModal.show("Error", appError.localizedDescription)
        }
    }
    
    private var displayedPDFFiles: [PDFFile] {
        guard libraryViewState.searchText.isEmpty == false else {
            return pdfFiles
        }

        return pdfFiles.filter {
            $0.url.lastPathComponent.contains(libraryViewState.searchText)
        }
    }

    private func searchTextFieldView() -> some View{
        HStack{
            TextField("Search", text:$libraryViewState.searchText)
                .textFieldStyle(.roundedBorder)
        }.padding()
    }

    private func pdfListView() -> some View{
        List{
            ForEach(displayedPDFFiles) { pdfFile in
                pdfRow(pdfFile)
            }
        }
    }

    private func pdfRow(_ pdfFile: PDFFile) -> some View {
        Text(pdfFile.url.lastPathComponent)
            .onTapGesture(count: 2) {
                openPDF(pdfFile)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Delete", role: .destructive) {
                    deletePDF(pdfFile)
                }

                Button("Copy File Path") {
                    do {
                        try copyFilePath(pdfFile)
                        libraryViewState.appError = nil
                    } catch {
                        libraryViewState.appError = AppError(error)
                    }
                }
            }
            .contextMenu {
                Button("Open PDF") {
                    openPDF(pdfFile)
                }

                Button("Copy File Path") {
                    do {
                        try copyFilePath(pdfFile)
                        libraryViewState.appError = nil
                    } catch {
                        libraryViewState.appError = AppError(error)
                    }
                }

                Button("Delete", role: .destructive) {
                    deletePDF(pdfFile)
                }
            }
    }


    
    func pdfView() -> some View{
        
        VStack(spacing: 8){
            if let selectedPDFFile = libraryViewState.selectedPDFFile{
                HStack {
                    Button("Back",action: {
                        closeDisplayedPDF()
                    })
                    
                    Menu("Translation") {
                        Button("Japanese") {
                            startTranslation(
                                libraryViewState.selectedPDFFile,
                                .japanese
                            )
                        }

                        Button("English") {
                            startTranslation(
                                libraryViewState.selectedPDFFile,
                                .english
                            )
                        }
                    }
                    .disabled(libraryViewState.isTranslating)
                    
                    Text(selectedPDFFile.resolvedURL.lastPathComponent )
                        .lineLimit(1)
                    
                    Spacer()
                    
                    
                    Button("Delete", role: .destructive,action: {
                        deleteDisplayedPDF(selectedPDFFile)
                    })
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                ZStack(alignment: .trailing) {
                    DirectoryPDFView(selectedPDFFile.resolvedURL, $libraryViewState.currentPageIndex)

                    TranslationResultView(
                        text: libraryViewState.translatedText, close: {
                            libraryViewState.isTranslationPresented = false
                        }
                    )
                    .frame(width: 500)
                    .background(.background)
                    .opacity(libraryViewState.isTranslationPresented ? 1 : 0)
                    .allowsHitTesting(libraryViewState.isTranslationPresented)
                    .accessibilityHidden(
                        libraryViewState.isTranslationPresented == false
                    )
                }
                
                
                if FileIO.exists(selectedPDFFile.resolvedURL) {
                    Text(selectedPDFFile.url.absoluteString)
                        .padding(.top, 15)
                        .padding(.bottom, 5)
                }else{
                    Text("File not found: \(selectedPDFFile.resolvedURL.absoluteString)")
                        .padding(.top, 15)
                        .padding(.bottom, 5)
                }
                
            }
            
        }
    }

    
    private func startTranslation(_ selectedPDFFile: PDFFile?,_ targetLanguage: TranslationLanguage) {
        guard let selectedPDFFile else {
            return
        }

        let resolvedURL = selectedPDFFile.resolvedURL

        libraryViewState.appError = nil

        Task {
            @MainActor in

            await Task.yield()

            guard FileIO.exists(resolvedURL) else {
                closeMissingPDF()

                await Task.yield()

                libraryViewState.appError = AppError.notFound("PDF File not found.")
                return
            }

            libraryViewState.isTranslating = true

            do {
                libraryViewState.textToTranslate = try await LibraryViewService.textForTranslation(resolvedURL, libraryViewState.currentPageIndex)

                if var configuration = libraryViewState.translationConfiguration {
                    configuration.source = targetLanguage.opposite.localeLanguage
                    
                    configuration.target = targetLanguage.localeLanguage
                    
                    configuration.preferredStrategy = .lowLatency
                    
                    configuration.invalidate()
                    
                    libraryViewState.translationConfiguration = configuration
                } else {
                    libraryViewState.translationConfiguration = TranslationSession.Configuration(source: targetLanguage.opposite.localeLanguage, target: targetLanguage.localeLanguage, preferredStrategy: .lowLatency )
                }
            } catch {
                libraryViewState.isTranslating = false

                if FileIO.exists(resolvedURL) {
                    libraryViewState.appError = AppError(error)
                } else {
                    closeMissingPDF()

                    await Task.yield()

                    libraryViewState.appError = AppError.notFound("PDF File not found.")
                }
            }
        }
    }
    
    
    private func openPDF(_ pdfFile: PDFFile) {
        libraryViewState.selectedPDFFile = pdfFile
    }

    private func deletePDF(_ pdfFile: PDFFile) {
        do {
            try LibraryViewService.delete(
                modelContext,
                pdfFile.url,
                pdfFile.resolvedURL
            )

            libraryViewState.selectedPDFFile = nil
            libraryViewState.appError = nil
        } catch {
            libraryViewState.appError = AppError(error)
        }
    }
    
    private func deleteDisplayedPDF(_ pdfFile: PDFFile) {
        let url = pdfFile.url
        
        let resolvedURL = pdfFile.resolvedURL

        libraryViewState.isTranslationPresented = false
        
        libraryViewState.isTranslating = false
        
        libraryViewState.selectedPDFFile = nil
        
        libraryViewState.appError = nil

        Task {
            @MainActor in
            
            await Task.yield()

            do {
                try LibraryViewService.delete(modelContext, url, resolvedURL)
                
                libraryViewState.textToTranslate = String()
                
                libraryViewState.translatedText = String()
                
            } catch {
                libraryViewState.appError = AppError(error)
            }
        }
    }

    private func closeDisplayedPDF() {
        libraryViewState.isTranslationPresented = false
        
        libraryViewState.isTranslating = false

        Task {
            @MainActor in
     
            await Task.yield()
            
            libraryViewState.selectedPDFFile = nil
        }
    }

    private func closeMissingPDF() {
        libraryViewState.isTranslationPresented = false

        libraryViewState.isTranslating = false

        libraryViewState.selectedPDFFile = nil

        libraryViewState.textToTranslate = String()

        libraryViewState.translatedText = String()
    }

    private func copyFilePath(_ pdfFile: PDFFile) throws {
        let resolvedURL = pdfFile.resolvedURL

        if FileIO.exists(resolvedURL) == false {
            throw AppError.notFound("PDF File not found.")
        }

        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString(resolvedURL.path, forType: .string)
    }
}

private struct TranslationResultView: View {
    let text: String
    let close: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            
            HStack {
                Text("Translation").font(.headline)

                Spacer()

                Button("Close", action: close)
            }
            .padding()

            Divider()

            ReadOnlyTextView(text: text)
        }
    }
}

private struct ReadOnlyTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 12, height: 12)
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true

        let scrollView = NSScrollView()

        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard
            let textView = scrollView.documentView as? NSTextView,
            textView.string != text
        else {
            return
        }

        textView.string = text
    }
}

#Preview {
    LibraryView()
}
