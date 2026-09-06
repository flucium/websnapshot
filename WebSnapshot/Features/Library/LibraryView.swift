import SwiftUI
import SwiftData
import Translation
import AppKit

struct LibraryView:View {

    @Environment(\.modelContext) private var modelContext

    @Query private var pdfFiles: [PDFFile]

    @StateObject private var libraryViewState = LibraryViewState()
    @StateObject private var pdfFileMonitor = LibraryPDFFileMonitor()

    
    var body: some View {
        VStack{
            
            if libraryViewState.selectedPDFFile == nil{
                HStack{
                    searchTextFieldView()
                    
                    searchTextModeView()
                }.padding(.horizontal)
                pdfListView()
            }else{
                pdfView()
            }
        }
        .onDisappear {
            pdfFileMonitor.stop()
            libraryViewState.cancelTranslation()
        }
        .onChange(of: monitoredPDFFilePaths) {
            scheduleSynchronizeLibraryFiles()
        }
        .task {
            await synchronizeLibraryFilesAfterViewUpdate()

            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }

                await synchronizeLibraryFilesAfterViewUpdate()
            }
        }
        .background {
            translationTaskView
        }
        .alert(
            item: $libraryViewState.appError
        ) { appError in
            AlertModal.show(libraryViewState.errorTitle, appError)
        }
        .sheet(
            item: $libraryViewState.tagEditorPDFFile,
            onDismiss: libraryViewState.closeTagEditor
        ) { pdfFile in
            LibraryTagEditorView(
                libraryViewState: libraryViewState,
                pdfFile: pdfFile
            )
        }
    }

    @ViewBuilder
    private var translationTaskView: some View {
        if let request = libraryViewState.translationRequest, request.text != nil {
            Color.clear
                .frame(width: 0, height: 0)
                .translationTask(request.configuration) { session in
                    await LibraryViewService.translate(libraryViewState, session, request)
                }
                .id(request.id)
        }
    }

    private var monitoredPDFFilePaths: [String] {
        pdfFiles.map {
            $0.resolvedURL.standardizedFileURL.path
        }
        .sorted()
    }

    private var existingPDFFiles: [PDFFile] {
        pdfFiles.filter {
            $0.availability != .missing
        }
    }
    
    private var displayedPDFFiles: [PDFFile] {
        return existingPDFFiles.filter {
            LibraryViewService.matches(
                $0,
                libraryViewState.searchText,
                libraryViewState.selectedSearchMode
            )
        }
    }

    private func searchTextFieldView() -> some View{
        HStack{
            TextField("Search", text:$libraryViewState.searchText)
                .textFieldStyle(.roundedBorder)
        }.padding(.top,10)
    }

    private func searchTextModeView() -> some View{
        Picker("Search mode", selection: $libraryViewState.selectedSearchMode) {
            ForEach(SearchMode.allCases, id: \.self) { searchMode in
                Text(searchMode.title)
                    .tag(searchMode)
            }
        }
        .pickerStyle(.radioGroup)
        .horizontalRadioGroupLayout()
    }

    private func pdfListView() -> some View{
        List{
            ForEach(displayedPDFFiles) { pdfFile in
                pdfRow(pdfFile)
            }
        }
    }

    private func pdfRow(_ pdfFile: PDFFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pdfFile.resolvedURL.lastPathComponent)

            if pdfFile.tags.isEmpty == false {
                HStack(spacing: 6) {
                    ForEach(rowTags(pdfFile)) { tag in
                        PDFTagBadge(tag.name)
                    }

                    if pdfFile.tags.count > rowTags(pdfFile).count {
                        Text("+\(pdfFile.tags.count - rowTags(pdfFile).count)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) {
                openPDF(pdfFile)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button("Delete", role: .destructive) {
                    LibraryViewService.deletePDF(libraryViewState, modelContext, pdfFile)
                }

                Button("Copy File Path") {
                    LibraryViewService.copyFilePath(libraryViewState, pdfFile)
                }
            }
            .contextMenu {
                Button("Open PDF") {
                    openPDF(pdfFile)
                }

                Button("Edit Tags…") {
                    editTags(pdfFile)
                }

                Button("Copy File Path") {
                    LibraryViewService.copyFilePath(libraryViewState, pdfFile)
                }

                Button("Delete", role: .destructive) {
                    LibraryViewService.deletePDF(libraryViewState, modelContext, pdfFile)
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
                            LibraryViewService.startTranslation(
                                libraryViewState,
                                .japanese
                            )
                        }

                        Button("English") {
                            LibraryViewService.startTranslation(
                                libraryViewState,
                                .english
                            )
                        }
                    }
                    .disabled(libraryViewState.isTranslating)
                    
                    Text(selectedPDFFile.resolvedURL.lastPathComponent )
                        .lineLimit(1)
                    
                    Spacer()
                    
                    
                    Button("Delete", role: .destructive,action: {
                        LibraryViewService.deleteDisplayedPDF(libraryViewState, modelContext, selectedPDFFile)
                    })

                    Button("Edit Tags…") {
                        editTags(selectedPDFFile)
                    }
                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                ZStack(alignment: .trailing) {
                    DirectoryPDFView(
                        selectedPDFFile.resolvedURL,
                        libraryViewState
                    )

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
                
                
//                if FileIO.exists(selectedPDFFile.resolvedURL) {
//                    Text(selectedPDFFile.url.absoluteString)
//                        .padding(.top, 15)
//                        .padding(.bottom, 5)
//                }else{
//                    Text("The PDF file could not be found.")
//                        .padding(.top, 15)
//                        .padding(.bottom, 5)
//                }
                
            }
            
        }
    }

    
    private func openPDF(_ pdfFile: PDFFile) {
        libraryViewState.selectedPDFFile = pdfFile
    }

    private func editTags(_ pdfFile: PDFFile) {
        libraryViewState.presentTagEditor(pdfFile)
    }

    private func rowTags(_ pdfFile: PDFFile) -> [PDFTag] {
        Array(
            pdfFile.tags
                .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                .prefix(5)
        )
    }

    private func closeDisplayedPDF() {
        libraryViewState.cancelTranslation()

        Task {
            @MainActor in
     
            await Task.yield()
            
            libraryViewState.selectedPDFFile = nil
        }
    }

    private func scheduleSynchronizeLibraryFiles() {
        Task { @MainActor in
            await synchronizeLibraryFilesAfterViewUpdate()
        }
    }

    private func synchronizeLibraryFilesAfterViewUpdate() async {
        do {
            try await Task.sleep(nanoseconds: 50_000_000)
        } catch {
            return
        }

        LibraryViewService.synchronizeLibraryFiles(libraryViewState, modelContext, pdfFileMonitor)
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
