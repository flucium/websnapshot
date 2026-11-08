import SwiftUI
import SwiftData
import WebKit

struct FetchView: View {
    
    @Environment(\.modelContext) private var modelContext

    @EnvironmentObject private var librarySyncService: LibrarySyncService
    
    @StateObject private var fetchViewState = FetchViewState()

    @Query private var storageSettings: [StorageSettings]

    var body: some View {
        VStack{
            
            searchToolView()

            if fetchViewState.isSaving {
                exportProgressView()
            }
         
            webView()
        }
        .onChange(of: fetchViewState.webPage.url) {
            _, url in
            guard let url, url.isSupportedWebURL else {
                return
            }

            fetchViewState.searchText = url.absoluteString
        }
        .onDisappear {
            fetchViewState.cancelLoad()
        }
    }
    
    func searchToolView() -> some View{
        HStack {
            TextField("https://...",text: $fetchViewState.searchText)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    FetchViewService.loadWebPage(fetchViewState)
                }
            
            Button("Load", action: {
                FetchViewService.loadWebPage(fetchViewState)
            })
            .disabled(fetchViewState.searchText.isEmpty)
            
            Button("Clear",action:{
                fetchViewState.clear()
            })
            
            Button("Save", action: {
                FetchViewService.saveWebPage(fetchViewState,modelContext,storageSettings, sync: librarySyncService)
            })
            .disabled(fetchViewState.isSaving || fetchViewState.webPage.isLoading)

        }
        .alert(item:$fetchViewState.appError){
            appError in
            AlertModal.show(fetchViewState.failedOperation?.errorTitle ?? "Operation Could Not Be Completed",appError) {
                FetchViewService.retryFailedOperation(fetchViewState, modelContext, storageSettings, sync: librarySyncService)
            }
        }
        .padding()
    }

    private func exportProgressView() -> some View {
        HStack(spacing: 12) {
            ProgressView().controlSize(.small)

            VStack(alignment: .leading, spacing: 3) {
                Text(fetchViewState.isCancellingSave ? "Cancelling…" : fetchViewState.exportState?.title ?? "Preparing Page")
                    .font(.callout.weight(.medium))

                if let progress = fetchViewState.exportState {
                    Text(progress.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button("Cancel") {
                fetchViewState.cancelSave()
            }
            .disabled(fetchViewState.isCancellingSave)
        }
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    func webView() -> some View{
        ZStack{
            if fetchViewState.webPage.url == nil {
                Color(nsColor: .windowBackgroundColor)
            }else{
                WebView(fetchViewState.webPage)
                    .disabled(fetchViewState.isSaving)
                    .allowsHitTesting(!fetchViewState.isSaving)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}


#Preview {
    FetchView()
        .environmentObject(LibrarySyncService())
}
