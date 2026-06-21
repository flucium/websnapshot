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
        .fileExporter(
            isPresented: $singleViewState.isFileExporterPresented,
            document: singleViewState.pdfFileDocument,
            contentType: .pdf,
            defaultFilename: URL.pdfFileName(
                singleViewState.webPage.title,
                singleViewState.webPage.url
            ),
            onCompletion: handleFileExport
        )
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

                        singleViewState.isFileExporterPresented = true
                    }catch{
                        singleViewState.appError = AppError(error)
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

    private func handleFileExport(_ result: Result<URL, Error>) {
        switch result {
        case .success(let destinationURL):
            do {
                try PDFFileService.save(modelContext, destinationURL)
                singleViewState.appError = nil
            } catch {
                singleViewState.appError = AppError(error)
            }
        case .failure(let error):
            let cocoaError = error as NSError

            guard cocoaError.domain != NSCocoaErrorDomain || cocoaError.code != NSUserCancelledError else {
                return
            }

            singleViewState.appError = AppError(error)
        }
    }
    
    func webView() -> some View{
        ZStack{
            if singleViewState.webPage.url == nil {
                Rectangle()
                    .fill(.background)
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
