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
        .translationTask(libraryViewState.translationConfiguration) { session in
            guard libraryViewState.textToTranslate.isEmpty == false else {
                libraryViewState.isTranslating = false
                return
            }

            do {
                libraryViewState.translatedText = try await Translation.translate(session,libraryViewState.textToTranslate)

                libraryViewState.isTranslationPresented = true
            } catch {
                handle(
                    error,
                    "Translation Could Not Be Completed",
                    "Translate PDF text"
                )
            }

            libraryViewState.isTranslating = false
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

    private var monitoredPDFFilePaths: [String] {
        pdfFiles.map {
            $0.url.standardizedFileURL.path
        }
        .sorted()
    }

    private var existingPDFFiles: [PDFFile] {
        pdfFiles.filter {
            FileIO.exists($0.url)
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
        }.padding()
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
            Text(pdfFile.url.lastPathComponent)

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
                    deletePDF(pdfFile)
                }

                Button("Copy File Path") {
                    do {
                        try copyFilePath(pdfFile)
                        libraryViewState.appError = nil
                    } catch {
                        handle(
                            error,
                            "File Path Could Not Be Copied",
                            "Copy PDF path",
                            pdfFile.resolvedURL
                        )
                    }
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
                    do {
                        try copyFilePath(pdfFile)
                        libraryViewState.appError = nil
                    } catch {
                        handle(
                            error,
                            "File Path Could Not Be Copied",
                            "Copy PDF path",
                            pdfFile.resolvedURL
                        )
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

                present(
                    AppError.notFound("The PDF file could not be found."),
                    "PDF Could Not Be Opened",
                    "Open PDF",
                    resolvedURL
                )
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
                    handle(
                        error,
                        "Text Could Not Be Prepared",
                        "Prepare PDF text",
                        resolvedURL
                    )
                } else {
                    closeMissingPDF()

                    await Task.yield()

                    present(
                        AppError.notFound("The PDF file could not be found."),
                        "PDF Could Not Be Opened",
                        "Open PDF",
                        resolvedURL
                    )
                }
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
            handle(
                error,
                "PDF Could Not Be Deleted",
                "Delete PDF",
                pdfFile.resolvedURL
            )
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
                handle(
                    error,
                    "PDF Could Not Be Deleted",
                    "Delete PDF",
                    resolvedURL
                )
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
            throw AppError.notFound("The PDF file could not be found.")
        }

        let pasteboard = NSPasteboard.general

        pasteboard.clearContents()
        guard pasteboard.setString(resolvedURL.path, forType: .string) else {
            throw AppError.system("The file path could not be copied.")
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

        synchronizeLibraryFiles()
    }

    private func synchronizeLibraryFiles() {
        closeSelectedPDFIfMissing()

        do {
            try LibraryViewService.deleteMissingFiles(modelContext, pdfFiles)

            pdfFileMonitor.sync(existingPDFFiles) { missingURL in
                handleMissingPDF(missingURL)
            }
        } catch {
            handle(
                error,
                "Library Could Not Be Synchronized",
                "Synchronize PDF library"
            )
        }
    }

    private func handleMissingPDF(_ url: URL) {
        guard FileIO.exists(url) == false else {
            return
        }

        if selectedPDFPath == url.standardizedFileURL.path {
            closeMissingPDF()
        }

        do {
            try LibraryViewService.deleteMissingFiles(modelContext, pdfFiles)

            pdfFileMonitor.sync(existingPDFFiles) { missingURL in
                handleMissingPDF(missingURL)
            }
        } catch {
            handle(
                error,
                "Library Could Not Be Synchronized",
                "Synchronize PDF library",
                url
            )
        }
    }

    private func closeSelectedPDFIfMissing() {
        guard let selectedPDFFile = libraryViewState.selectedPDFFile else {
            return
        }

        guard FileIO.exists(selectedPDFFile.url) == false else {
            return
        }

        closeMissingPDF()
    }

    private var selectedPDFPath: String? {
        libraryViewState.selectedPDFFile?.url.standardizedFileURL.path
    }

    private func handle(
        _ error: Error,
        _ title: String,
        _ operation: String,
        _ targetURL: URL? = nil
    ) {
        guard let appError = AppError.presentable(error) else {
            return
        }

        present(appError, title, operation, targetURL)
    }

    private func present(
        _ appError: AppError,
        _ title: String,
        _ operation: String,
        _ targetURL: URL? = nil
    ) {
        guard appError.isCancellation == false else {
            return
        }

        AppLogger.record(appError, operation, targetURL)
        libraryViewState.errorTitle = title
        libraryViewState.appError = appError
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
