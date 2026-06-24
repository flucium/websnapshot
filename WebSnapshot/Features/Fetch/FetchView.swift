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
    }
    
    func searchToolView() -> some View{
        HStack {
            TextField("https://...",text: $fetchViewState.searchText)
                .textFieldStyle(.roundedBorder)
            .onSubmit {
                do{
                    fetchViewState.webPage = try FetchViewService.fetch(URL(string:fetchViewState.searchText)!)
                    fetchViewState.appError = nil
                }catch{
                    fetchViewState.appError = AppError(error)
                }
            }
            
            Button("Load", action: {
                do{
                    fetchViewState.webPage = try FetchViewService.fetch(URL(string:fetchViewState.searchText)!)
                    fetchViewState.appError = nil
                }catch{
                    fetchViewState.appError = AppError(error)
                }
            })
            .disabled(fetchViewState.searchText.isEmpty)
            
            Button("Clear",action:{
                fetchViewState.clear()
            })
            
            Button("Save", action: {
                Task{
                    do{
                        fetchViewState.pdfFileDocument = try await WebService.export(fetchViewState.webPage)

                        fetchViewState.appError = nil
                    }catch{
                        fetchViewState.appError = AppError(error)
                    }

                    guard let pdfFileDocument = fetchViewState.pdfFileDocument else {
                        return
                    }

                    do {
                        let destinationURL = try savePanel(fetchViewState.webPage.title, fetchViewState.webPage.url, pdfFileDocument)

                        if let destinationURL {
                            try PDFFileService.save(modelContext, destinationURL)
                        }

                        fetchViewState.appError = nil
                    } catch {
                        fetchViewState.appError = AppError(error)
                    }
                }
            })
        }
        .alert(
            item:$fetchViewState.appError
        ){
            appError in
            AlertModal.show("Error",appError.localizedDescription)
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
