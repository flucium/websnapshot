import SwiftUI
import SwiftData
import WebKit
import UniformTypeIdentifiers

struct SingleView: View {
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var singleViewState = SingleViewState()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                
                TextField("https://...", text: $singleViewState.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(singleViewState.load)
                
                Button("Load", action: singleViewState.load)
                
                Button("Save") {
                    Task {
                        if await singleViewState.save() {
                            await MainActor.run {
                                let url = savePanel()
                                save(url)
                            }
                        }
                    }
                }
                Button("Clear", action: singleViewState.clear)
            }
            .disabled(singleViewState.isSaving)
            .padding()
            
            ZStack {
                WebView(singleViewState.webPage)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(!singleViewState.isSaving)

                if singleViewState.isSaving {
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay {
                            ProgressView("Saving PDF...")
                                .padding(12)
                                .background(.regularMaterial)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                }
            }
        }
        .alert(
            "Save Failed",
            isPresented: Binding(
                get: {
                    singleViewState.error != nil
                },
                set: {
                    isPresented in
                    if isPresented == false{
                        singleViewState.error = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel,action: {})
        } message: {
            Text(singleViewState.error?.localizedDescription ?? "Unknown error.")
        }
    }
    
    @MainActor
    func savePanel() -> URL?{
        guard let data = singleViewState.pdfFileDocument?.data else{
            return nil
        }
        
        
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.canCreateDirectories = true
        panel.title = "Save"
        panel.nameFieldStringValue = URL.makePDFFileName(title: singleViewState.webPage.title,fallbackURL: singleViewState.webPage.url)

        guard panel.runModal() == .OK, let destination = panel.url else {
            return nil
        }
        
        do{
            try data.write(to: destination,options: .atomic)

            let directoryURL = destination.deletingLastPathComponent()

            if DirectoryHistoryService
                .exists(destination.deletingLastPathComponent(), modelContext) == false{
                try DirectoryHistoryService.save(directoryURL, modelContext)
            }
            
            return destination
        }catch{
            singleViewState.error = AppError( error)
            return nil
        }
    }
    
    func save(_ url: URL?) {
        guard let url else {
            return
        }

        do {
            try SingleViewService.save(url,modelContext)
            
            singleViewState.error = nil
        } catch {
            singleViewState.error = AppError( error)
        }
    }
}


#Preview {
    SingleView()
}
