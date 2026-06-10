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
                
                if directoryViewState.searchText.isEmpty == false{
                    listView()
                }else{
                    searchListView()
                }
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
    }
    
    func searchTextFieldView() -> some View{
        HStack{
            TextField("Search", text:$directoryViewState.searchText)
                .textFieldStyle(.roundedBorder)
        }.padding()
    }
    
    func listView() -> some View{
        List{
            ForEach(pdfFiles){
                pdfFile in
                
                if pdfFile.url.lastPathComponent.contains(directoryViewState.searchText){
                    Text("\(pdfFile.url.lastPathComponent)")
                        .onTapGesture(count: 2) {
                            directoryViewState.selectedPDFFile = pdfFile
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button("Delete", role: .destructive,action: {
                                do{
                                    try DirectoryViewService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL)
                                    
                                    directoryViewState.selectedPDFFile = nil
                                   
                                    directoryViewState.appError = nil
                                }catch{
                                    directoryViewState.appError = AppError(error)
                                }
                            })
                        }
                        .contextMenu {
                            Button("Open PDF", action: {
                                directoryViewState.selectedPDFFile = pdfFile
                            })
                            
                            Button("Delete", role: .destructive,action: {
                                do{
                                    try DirectoryViewService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL)
                                    
                                    directoryViewState.selectedPDFFile = nil
                                    
                                    directoryViewState.appError = nil
                                }catch{
                                    directoryViewState.appError = AppError(error)
                                }
                            })
                        }
                }
            }
        }.alert(
            item:$directoryViewState.appError
        ){
            appError in
            AlertModal.show("Error",appError.localizedDescription)
        }
    }
    
    func searchListView() -> some View{
        List{
            ForEach(pdfFiles){
                pdfFile in
                
                Text("\(pdfFile.url.lastPathComponent)")
                    .onTapGesture(count: 2) {
                        directoryViewState.selectedPDFFile = pdfFile
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button("Delete", role: .destructive,action: {
                            do{
                                try DirectoryViewService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL)
                                
                                directoryViewState.selectedPDFFile = nil
                                
                                directoryViewState.appError = nil
                            }catch{
                                directoryViewState.appError = AppError(error)
                            }
                        })
                    }
                    .contextMenu {
                        Button("Open PDF", action: {
                            directoryViewState.selectedPDFFile = pdfFile
                        })
                        
                        Button("Delete", role: .destructive,action: {
                            do{
                                try DirectoryViewService.delete(modelContext, pdfFile.url, pdfFile.resolvedURL)
                                
                                directoryViewState.selectedPDFFile = nil
                                
                                directoryViewState.appError = nil
                            }catch{
                                directoryViewState.appError = AppError(error)
                            }
                        })
                    }
            }
        }.alert(
            item:$directoryViewState.appError
        ){
            appError in
            AlertModal.show("Error",appError.localizedDescription)
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
                            startTranslation(directoryViewState.selectedPDFFile,.japanese)
                        }

                        Button("English") {
                            startTranslation(directoryViewState.selectedPDFFile,.english)
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
            }
        }
        .alert(
            item:$directoryViewState.appError
        ){
            appError in
            AlertModal.show("Error",appError.localizedDescription)
        }
    
    }

    
    private func startTranslation(_ selectedPDFFile: PDFFile?, _ targetLanguage: TranslationLanguage) {
        guard let selectedPDFFile else {
            return
        }

        directoryViewState.isTranslating = true
        
        directoryViewState.appError = nil

        Task {
            do {
                directoryViewState.textToTranslate = try await DirectoryViewService.textForTranslation(selectedPDFFile.resolvedURL, directoryViewState.currentPageIndex)

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
                
                directoryViewState.appError = AppError(error)
            }
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
            let textView = scrollView.documentView as? NSTextView, textView.string != text
        else {
            return
        }

        textView.string = text
    }
}

#Preview {
    DirectoryView()
}
