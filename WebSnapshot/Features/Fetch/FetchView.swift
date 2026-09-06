import SwiftUI
import SwiftData
import WebKit

struct FetchView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var fetchViewState = FetchViewState()

    @Query private var storageSettings: [StorageSettings]

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
                FetchViewService.saveWebPage(fetchViewState,modelContext,storageSettings)
            })
        }
        .alert(
            item:$fetchViewState.appError
        ){
            appError in
            AlertModal.show(
                fetchViewState.failedOperation?.errorTitle ?? "Operation Could Not Be Completed",
                appError
            ) {
                FetchViewService.retryFailedOperation(fetchViewState, modelContext, storageSettings)
            }
        }
        .padding()
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
