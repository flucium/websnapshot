import SwiftUI
import SwiftData
import WebKit

struct FetchView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var fetchViewState = FetchViewState()

    var body: some View {
        VStack{
            
            searchToolView()
         
            webView()
        }
        .onChange(of: fetchViewState.webPage.url) {
            _, url in
            guard let url, url.isSupportedWebURL else {
                return
            }

            fetchViewState.searchText = url.absoluteString
        }
    }
    
    func searchToolView() -> some View{
        HStack {
            TextField("https://...",text: $fetchViewState.searchText)
                .textFieldStyle(.roundedBorder)
            .onSubmit {
                loadWebPage()
            }
            
            Button("Load", action: {
                loadWebPage()
            })
            .disabled(fetchViewState.searchText.isEmpty)
            
            Button("Clear",action:{
                fetchViewState.clear()
            })
            
            Button("Save", action: {
                saveWebPage()
            })
        }
        .alert(
            item:$fetchViewState.appError
        ){
            appError in
            AlertModal.show(
                fetchViewState.failedOperation?.errorTitle ?? "Operation Could Not Be Completed",
                appError,
                retryFailedOperation
            )
        }
        .padding()
    }

    private func loadWebPage() {
        Task {
            do {
                fetchViewState.webPage = try await FetchViewService.fetch(fetchViewState.searchText)
                fetchViewState.appError = nil
                fetchViewState.failedOperation = nil
            } catch {
                handle(error, .load)
            }
        }
    }

    private func saveWebPage() {
        Task {
            do {
                let document = try await WebService.export(fetchViewState.webPage)
                fetchViewState.pdfFileDocument = document

                guard let destinationURL = try savePanel(
                    fetchViewState.webPage.title,
                    fetchViewState.webPage.url,
                    document
                ) else {
                    return
                }

                try PDFFileService.save(modelContext, destinationURL)
                fetchViewState.appError = nil
                fetchViewState.failedOperation = nil
            } catch {
                handle(error, .save)
            }
        }
    }

    private func handle(_ error: Error, _ operation: FetchViewState.Operation) {
        guard let appError = AppError.presentable(error) else {
            return
        }

        AppLogger.record(
            appError,
            operation == .load ? "Load webpage" : "Save webpage as PDF",
            operation == .load
                ? URL.supportedWebURL(fetchViewState.searchText)
                : fetchViewState.webPage.url
        )
        fetchViewState.failedOperation = operation
        fetchViewState.appError = appError
    }

    private func retryFailedOperation() {
        switch fetchViewState.failedOperation {
        case .load:
            loadWebPage()
        case .save:
            saveWebPage()
        case nil:
            break
        }
    }

    func webView() -> some View{
        ZStack{
            if fetchViewState.webPage.url == nil {
                Color(nsColor: .windowBackgroundColor)
            }else{
                WebView(fetchViewState.webPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}


#Preview {
    FetchView()
}
