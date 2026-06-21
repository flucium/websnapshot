import SwiftUI
import SwiftData
import Translation

struct DirectoryView:View {

    @Environment(\.modelContext) private var modelContext

    @Query private var pdfFiles: [PDFFile]

    @StateObject private var directoryViewState = DirectoryViewState()

    
    var body: some View {
        VStack{
            
            if directoryViewState.selectedPDFFile == nil{
                searchTextFieldView()

                pdfListView()
            }else{
                pdfView()
            }
        }
        .translationTask(directoryViewState.translationConfiguration) { session in
            guard directoryViewState.textToTranslate.isEmpty == false else {
                directoryViewState.isTranslating = false
                return
            }

            do {
                directoryViewState.translatedText = try await Translation.translate(
                    using: session,
                    directoryViewState.textToTranslate
                )

                directoryViewState.isTranslationPresented = true
            } catch {
                directoryViewState.appError = AppError(error)
            }

            directoryViewState.isTranslating = false
        }
        .alert(
            item: $directoryViewState.appError
        ) { appError in
            AlertModal.show("Error", appError.localizedDescription)
        }
    }
    
    private var displayedPDFFiles: [PDFFile] {
        guard directoryViewState.searchText.isEmpty == false else {
            return pdfFiles
        }

        return pdfFiles.filter {
            $0.url.lastPathComponent.contains(directoryViewState.searchText)
        }
    }

    private func searchTextFieldView() -> some View{
        HStack{
            TextField("Search", text:$directoryViewState.searchText)
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

#if os(macOS)
                Button("Copy File Path") {
                    do {
                        try copyFilePath(pdfFile)
                        directoryViewState.appError = nil
                    } catch {
                        directoryViewState.appError = AppError(error)
                    }
                }
#endif
            }
            .contextMenu {
                Button("Open PDF") {
                    openPDF(pdfFile)
                }

#if os(macOS)
                Button("Copy File Path") {
                    do {
                        try copyFilePath(pdfFile)
                        directoryViewState.appError = nil
                    } catch {
                        directoryViewState.appError = AppError(error)
                    }
                }
#elseif os(iOS)
                ShareLink(item: pdfFile.resolvedURL) {
                    Label("Share PDF", systemImage: "square.and.arrow.up")
                }
#endif

                Button("Delete", role: .destructive) {
                    deletePDF(pdfFile)
                }
            }
    }


    
    func pdfView() -> some View{
        
        VStack(spacing: 8){
            if let selectedPDFFile = directoryViewState.selectedPDFFile{
                HStack {
                    Button("Back",action: {
                        closeDisplayedPDF()
                    })
                    
                    Menu("Translation") {
                        Button("Japanese") {
                            startTranslation(
                                directoryViewState.selectedPDFFile,
                                .japanese
                            )
                        }

                        Button("English") {
                            startTranslation(
                                directoryViewState.selectedPDFFile,
                                .english
                            )
                        }
                    }
                    .disabled(directoryViewState.isTranslating)
                    
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
                    DirectoryPDFView(selectedPDFFile.resolvedURL, $directoryViewState.currentPageIndex)

                    TranslationResultView(
                        text: directoryViewState.translatedText, close: {
                            directoryViewState.isTranslationPresented = false
                        }
                    )
                    .frame(width: 500)
                    .background(.background)
                    .opacity(directoryViewState.isTranslationPresented ? 1 : 0)
                    .allowsHitTesting(directoryViewState.isTranslationPresented)
                    .accessibilityHidden(
                        directoryViewState.isTranslationPresented == false
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

    
    private func startTranslation(
        _ selectedPDFFile: PDFFile?,
        _ targetLanguage: TranslationLanguage
    ) {
        guard let selectedPDFFile else {
            return
        }

        let resolvedURL = selectedPDFFile.resolvedURL

        directoryViewState.appError = nil

        Task {
            @MainActor in

            await Task.yield()

            guard FileIO.exists(resolvedURL) else {
                closeMissingPDF()

                await Task.yield()

                directoryViewState.appError = AppError.notFound("PDF File not found.")
                return
            }

            directoryViewState.isTranslating = true

            do {
                directoryViewState.textToTranslate = try await DirectoryViewService.textForTranslation(resolvedURL, directoryViewState.currentPageIndex)

                if var configuration = directoryViewState.translationConfiguration {
                    configuration.source = targetLanguage.opposite.localeLanguage
                    
                    configuration.target = targetLanguage.localeLanguage
                    
                    configuration.preferredStrategy = .lowLatency
                    
                    configuration.invalidate()
                    
                    directoryViewState.translationConfiguration = configuration
                } else {
                    directoryViewState.translationConfiguration = TranslationSession.Configuration(source: targetLanguage.opposite.localeLanguage, target: targetLanguage.localeLanguage, preferredStrategy: .lowLatency )
                }
            } catch {
                directoryViewState.isTranslating = false

                if FileIO.exists(resolvedURL) {
                    directoryViewState.appError = AppError(error)
                } else {
                    closeMissingPDF()

                    await Task.yield()

                    directoryViewState.appError = AppError.notFound("PDF File not found.")
                }
            }
        }
    }
    
    
    private func openPDF(_ pdfFile: PDFFile) {
        directoryViewState.selectedPDFFile = pdfFile
    }

    private func deletePDF(_ pdfFile: PDFFile) {
        do {
            try DirectoryViewService.delete(
                modelContext,
                pdfFile.url,
                pdfFile.resolvedURL
            )

            directoryViewState.selectedPDFFile = nil
            directoryViewState.appError = nil
        } catch {
            directoryViewState.appError = AppError(error)
        }
    }
    
    private func deleteDisplayedPDF(_ pdfFile: PDFFile) {
        let url = pdfFile.url
        
        let resolvedURL = pdfFile.resolvedURL

        directoryViewState.isTranslationPresented = false
        
        directoryViewState.isTranslating = false
        
        directoryViewState.selectedPDFFile = nil
        
        directoryViewState.appError = nil

        Task {
            @MainActor in
            
            await Task.yield()

            do {
                try DirectoryViewService.delete(modelContext, url, resolvedURL)
                
                directoryViewState.textToTranslate = String()
                
                directoryViewState.translatedText = String()
                
            } catch {
                directoryViewState.appError = AppError(error)
            }
        }
    }

    private func closeDisplayedPDF() {
        directoryViewState.isTranslationPresented = false
        
        directoryViewState.isTranslating = false

        Task {
            @MainActor in
     
            await Task.yield()
            
            directoryViewState.selectedPDFFile = nil
        }
    }

    private func closeMissingPDF() {
        directoryViewState.isTranslationPresented = false

        directoryViewState.isTranslating = false

        directoryViewState.selectedPDFFile = nil

        directoryViewState.textToTranslate = String()

        directoryViewState.translatedText = String()
    }

#if os(macOS)
    private func copyFilePath(_ pdfFile: PDFFile) throws {
        let resolvedURL = pdfFile.resolvedURL

        if FileIO.exists(resolvedURL) == false {
            throw AppError.notFound("PDF File not found.")
        }

        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        pasteboard.setString(resolvedURL.path, forType: .string)
    }
#endif
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

private struct ReadOnlyTextView: View {
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
        }
    }
}

#Preview {
    DirectoryView()
}
