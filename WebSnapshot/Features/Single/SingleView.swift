import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers

struct SingleView: View {
    
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var singleViewState = SingleViewState()
    
    var body: some View {
        VStack{
            
            searchToolView()
         
            webView()
        }
    }
    
    func searchToolView() -> some View{
        HStack {
            TextField("https://...",text: $singleViewState.searchText)
                .textFieldStyle(.roundedBorder)
            .onSubmit {
                do{
                    singleViewState.webPage = try SingleViewService.fetch(URL(string:singleViewState.searchText)!)
                    singleViewState.appError = nil
                }catch{
                    singleViewState.appError = AppError(error)
                }
            }
            
            Button("Load", action: {
                do{
                    singleViewState.webPage = try SingleViewService.fetch(URL(string:singleViewState.searchText)!)
                    singleViewState.appError = nil
                }catch{
                    singleViewState.appError = AppError(error)
                }
            })
            .disabled(singleViewState.searchText.isEmpty)
            
            Button("Clear",action:{
                singleViewState.clear()
            })
            
            Button("Save", action: {
                Task{
                    do{
                        singleViewState.pdfFileDocument = try await WebService.export(singleViewState.webPage)
                        
                        singleViewState.appError = nil
                    }catch{
                        singleViewState.appError = AppError(error)
                    }
                    
                    
                    if singleViewState.pdfFileDocument == nil{
                        return
                    }
                    
                    await MainActor.run{
                        do{
                            let directoryURL = try savePanel(singleViewState.webPage.title,singleViewState.webPage.url,singleViewState.pdfFileDocument)
                            
                            if directoryURL != nil{
                                try PDFFileService.save(modelContext,directoryURL!)
                            }
                            
                            singleViewState.appError = nil
                        }catch{
                            singleViewState.appError = AppError(error)
                        }
                        
                    }
                }
            })
        }
        .alert(
            item:$singleViewState.appError
        ){
            appError in
            AlertModal.show("Error",appError.localizedDescription)
        }
        .padding()
    }
    
    func webView() -> some View{
        ZStack{
            if singleViewState.webPage.url == nil {
                Color(nsColor: .windowBackgroundColor)
            }else{
                WebView(singleViewState.webPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}


#Preview {
    SingleView()
}
