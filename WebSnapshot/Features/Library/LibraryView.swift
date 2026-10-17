import SwiftUI
import SwiftData
import Translation
import AppKit

struct LibraryView:View {

    @StateObject private var libraryViewState = LibraryViewState()
    
    @StateObject private var pdfFileMonitor = LibraryPDFFileMonitor()
    
    @EnvironmentObject private var contentService: LibraryContentService

    @EnvironmentObject private var sync: LibrarySyncService

    @Environment(\.modelContext) private var modelContext

    @Query private var pdfFiles: [PDFFile]
    
    @Query private var pdfTags: [PDFTag]

    
    private var contentState: LibraryContentState { contentService.state }

    
    var body: some View {
        Group {
            if libraryViewState.selectedPDFFile == nil {
                libraryContentView()
            } else {
                pdfView()
            }
        }
        .onDisappear {
            pdfFileMonitor.stop()
            
            libraryViewState.cancelTranslation()
        }
        .onChange(of: monitoredPDFFilePaths) {
            LibraryViewService.scheduleSynchronizeLibraryFiles(libraryViewState, modelContext, pdfFileMonitor, sync: sync)
        }
        .onChange(of: availableTagNames) { _, names in
            if case .tag(let selectedName) = libraryViewState.selectedTag, names.contains(selectedName) == false {
                libraryViewState.selectedTag = .all
            }
        }
        .onChange(of: displayedPDFFileIDs) { _, ids in
            if let selectedID = libraryViewState.selectedPDFRowID, ids.contains(selectedID) == false {
                libraryViewState.selectedPDFRowID = nil
            }
        }
        .task {
            await LibraryViewService.synchronizeLibraryFilesAfterViewUpdate(libraryViewState, modelContext, pdfFileMonitor, sync: sync)

            while Task.isCancelled == false {
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }

                await LibraryViewService.synchronizeLibraryFilesAfterViewUpdate(libraryViewState, modelContext, pdfFileMonitor, sync: sync)
            }
        }
        .background {
            translationTaskView
        }
        .task(priority: .utility) {
            while Task.isCancelled == false {
                await contentService.index(pdfFiles, modelContext)
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch {
                    break
                }
            }
        }
        .alert(item: $libraryViewState.appError) {
            appError in
            AlertModal.show(libraryViewState.errorTitle, appError)
        }
        .sheet(item: $libraryViewState.tagEditorPDFFile,onDismiss: libraryViewState.closeTagEditor) {
            pdfFile in
            LibraryTagEditorView(libraryTagEditorViewState: libraryViewState.libraryTagEditorViewState,pdfFile: pdfFile,close: libraryViewState.closeTagEditor)
        }
    }

    private func libraryContentView() -> some View {
        HSplitView {
            tagSidebar()

            VStack {
                HStack {
                    searchTextFieldView()

                    searchTextModeView()
                }
                .padding(.horizontal)

                if contentState.pendingCount > 0 {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Preparing content search… (\(contentState.pendingCount) PDFs remaining)")
                            .font(.caption)
                        Spacer()
                    }
                    .padding(.horizontal)
                } else if contentState.failedCount > 0 {
                    HStack {
                        Text("Content search is unavailable for some PDFs.")
                            .font(.caption)
                        Button("Retry", action: contentService.retry)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                HStack {
                    Button("Import PDFs…") {
                        LibraryViewService.importPDFs(libraryViewState, modelContext, sync: sync)
                    }

                    Button("Export PDF…") {
                        if let selectedPDFRow {
                            LibraryViewService.exportPDF(libraryViewState, selectedPDFRow)
                        }
                    }
                    .disabled(selectedPDFRow == nil)

                    Spacer()
                }
                .padding(.horizontal)

                pdfListView()

                if let selectedPDFRow {
                    Divider()
                    pdfMetadataView(selectedPDFRow)
                }
            }
            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    @ViewBuilder
    private var translationTaskView: some View {
        if let request = libraryViewState.translationRequest, request.text != nil {
            Color.clear.frame(width: 0, height: 0).translationTask(request.configuration) {
                session in
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

    private var availableTags: [PDFTag] {
        let existingFileIDs = Set(existingPDFFiles.map(\.persistentModelID))

        return pdfTags.filter { tag in
            tag.pdfFiles.contains { existingFileIDs.contains($0.persistentModelID) }
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private var availableTagNames: [String] {
        availableTags.map(\.normalizedName)
    }
    
    private var displayedPDFFiles: [PDFFile] {
        return existingPDFFiles.filter {
            pdfFile in

            let matchesSelectedTag = switch libraryViewState.selectedTag {
            case .all:
                true
            case .untagged:
                pdfFile.tags.isEmpty
            case .tag(let name):
                pdfFile.tags.contains { $0.normalizedName == name }
            }

            return matchesSelectedTag && LibraryService.matches(pdfFile,libraryViewState.searchText,libraryViewState.selectedSearchMode)
        }
    }

    private var displayedPDFFileIDs: [PersistentIdentifier] {
        displayedPDFFiles.map(\.persistentModelID)
    }

    private var selectedPDFRow: PDFFile? {
        guard let selectedID = libraryViewState.selectedPDFRowID else {
            return nil
        }

        return displayedPDFFiles.first { $0.persistentModelID == selectedID }
    }

    private func tagSidebar() -> some View {
        List(selection: $libraryViewState.selectedTag) {
            Section("Tags") {
                Label("All PDFs", systemImage: "square.stack")
                    .tag(LibraryViewState.TagSelection.all)

                Label("Untagged", systemImage: "tag.slash")
                    .tag(LibraryViewState.TagSelection.untagged)

                ForEach(availableTags) { tag in
                    Label(tag.name, systemImage: "tag")
                        .tag(LibraryViewState.TagSelection.tag(tag.normalizedName))
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .frame(minWidth: 165, idealWidth: 205, maxWidth: 260)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func searchTextFieldView() -> some View{
        HStack{
            TextField("Search", text:$libraryViewState.searchText)
                .textFieldStyle(.roundedBorder)
        }
        .padding(.top,10)
    }

    private func searchTextModeView() -> some View{
        Picker("Search mode", selection: $libraryViewState.selectedSearchMode) {
            ForEach(LibrarySearchMode.allCases, id: \.self) {
                searchMode in
                Text(searchMode.title)
                    .tag(searchMode)
            }
        }
        .pickerStyle(.radioGroup)
        .horizontalRadioGroupLayout()
    }

    private func pdfListView() -> some View{
        List(selection: $libraryViewState.selectedPDFRowID) {
            ForEach(displayedPDFFiles) { pdfFile in
                pdfRow(pdfFile)
                    .tag(pdfFile.persistentModelID)
            }
        }
        .onExitCommand {
            libraryViewState.selectedPDFRowID = nil
        }
    }

    private func pdfMetadataView(_ pdfFile: PDFFile) -> some View {
        let path = pdfFile.resolvedURL.path

        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Details")
                    .font(.headline)

                Spacer()

                Button {
                    libraryViewState.selectedPDFRowID = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .help("Clear selection")
                .accessibilityLabel("Clear selection")
            }

            if let addedAt = pdfFile.addedAt {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Date Added")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(addedAt, format: .dateTime.year().month().day())
                        .font(.subheadline)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("File Path")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(path)
                    .font(.subheadline)
                    .textSelection(.enabled)
                    .lineLimit(3)
                    .truncationMode(.middle)
                    .help(path)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func pdfRow(_ pdfFile: PDFFile) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(pdfFile.resolvedURL.lastPathComponent)

            if libraryViewState.downloadingPDFs.contains(pdfFile.persistentModelID) {
                
                Text("Downloading from iCloud…").font(.caption).foregroundStyle(.secondary)
                
            } else if pdfFile.syncRelativePath != nil, pdfFile.availability != .available {
                
                Text("In iCloud — open to download").font(.caption).foregroundStyle(.secondary)
                
            }

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
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            LibraryViewService.openPDF(libraryViewState, modelContext, pdfFile, sync: sync)
        })
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                LibraryViewService.deletePDF(libraryViewState, modelContext, pdfFile, sync: sync)
            }

            Button("Copy File Path") {
                LibraryViewService.copyFilePath(libraryViewState, pdfFile)
            }
        }
        .contextMenu {
            Button("Open PDF") {
                LibraryViewService.openPDF(libraryViewState, modelContext, pdfFile, sync: sync)
            }
            
            Button("Edit Tags…") {
                editTags(pdfFile)
            }

            Button("Export PDF…") {
                LibraryViewService.exportPDF(libraryViewState, pdfFile)
            }
            
            Button("Copy File Path") {
                LibraryViewService.copyFilePath(libraryViewState, pdfFile)
            }
            
            Button("Delete", role: .destructive) {
                LibraryViewService.deletePDF(libraryViewState, modelContext, pdfFile, sync: sync)
            }
        }
    }

    func pdfView() -> some View{
        
        VStack(spacing: 8){
            if let selectedPDFFile = libraryViewState.selectedPDFFile{
                HStack {
                    Button("Back",action: {
                        LibraryViewService.closeDisplayedPDF(libraryViewState)
                    })
                    
                    Menu("Translation") {
                        Button("Japanese") {
                            LibraryViewService.startTranslation(libraryViewState,.japanese)
                        }

                        Button("English") {
                            LibraryViewService.startTranslation(libraryViewState,.english)
                        }
                    }
                    .disabled(libraryViewState.isTranslating)
                    
                    Text(selectedPDFFile.resolvedURL.lastPathComponent )
                        .lineLimit(1)
                    
                    Spacer()

                    Button("Export PDF…") {
                        LibraryViewService.exportPDF(libraryViewState, selectedPDFFile)
                    }

                    Button("Edit Tags") {
                        editTags(selectedPDFFile)
                    }
                    
                    Button("Delete", role: .destructive,action: {
                        LibraryViewService.deleteDisplayedPDF(libraryViewState, modelContext, selectedPDFFile, sync: sync)
                    })


                }
                .padding(.horizontal)
                .padding(.top, 8)
                
                ZStack(alignment: .trailing) {
                    LibraryPDFView(selectedPDFFile.resolvedURL,libraryViewState)

                    TranslationResultView(
                        text: libraryViewState.translatedText, close: {
                            libraryViewState.isTranslationPresented = false
                        }
                    )
                    .frame(width: 500)
                    .background(.background)
                    .opacity(libraryViewState.isTranslationPresented ? 1 : 0)
                    .allowsHitTesting(libraryViewState.isTranslationPresented)
                    .accessibilityHidden(libraryViewState.isTranslationPresented == false)
                }
            }
            
        }
    }

    
    private func editTags(_ pdfFile: PDFFile) {
        libraryViewState.presentTagEditor(pdfFile)
    }

    private func rowTags(_ pdfFile: PDFFile) -> [PDFTag] {
        Array(pdfFile.tags.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }.prefix(5))
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
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else {
            return
        }

        textView.string = text
    }
}

private struct PDFTagBadge: View {
    let name: String

    init(_ name: String) {
        self.name = name
    }

    var body: some View {
        Label(name, systemImage: "tag")
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.quaternary, in: Capsule())
    }
}

#Preview {
    let sync = LibrarySyncService()
    let contentService = LibraryContentService(sync: sync)

    LibraryView()
        .environmentObject(contentService)
        .environmentObject(sync)
}
