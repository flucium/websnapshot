//
//  SingleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct SingleView: View {
    @Environment(\.modelContext) private var modelContext
    
    @StateObject private var singleWebViewModel = SingleViewModel()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("https://...", text: $singleWebViewModel.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        singleWebViewModel.load()
                    }
                
                Button("Load") {
                    singleWebViewModel.load()
                }
                
                Button("Save"){
                    singleWebViewModel.save()
                }
                
                Button("Clear") {
                    singleWebViewModel.clear()
                }
            }
            .padding()
            
            Text(singleWebViewModel.status)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)
            
            WebViewContainer(webView: singleWebViewModel.webPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }.fileExporter(
            isPresented: $singleWebViewModel.isExporting,
            document: singleWebViewModel.exportDocument,
            contentType: .pdf,
            defaultFilename: singleWebViewModel.suggestedFileName(),
        ) { result in
            switch result {
            case .success(let savedURL):
                modelContext.insert(PDFFileHistoryEntry(url: savedURL))

                do {
                    try modelContext.save()
                    singleWebViewModel.status = "Saved: \(savedURL.lastPathComponent)"
                } catch {
                    singleWebViewModel.errorState.setError(
                        .display(message: "Failed to save history: \(error.localizedDescription)")
                    )
                    singleWebViewModel.status = singleWebViewModel.errorState.status
                }

            case .failure(let error):
                singleWebViewModel.errorState.setError(
                    .display(message: "Export failed: \(error.localizedDescription)")
                )
                singleWebViewModel.status = singleWebViewModel.errorState.status
            }
        }
        
    }

}

#Preview {
    SingleView()
}
