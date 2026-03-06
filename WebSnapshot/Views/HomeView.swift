//
//  HomeView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct HomeView: View {
    @StateObject private var homeViewModel = HomeViewModel()

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                TextField("https://...", text: $homeViewModel.urlString)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        homeViewModel.load()
                    }

                Button("Load") { homeViewModel.load() }
                
                Button("Save as PDF") { homeViewModel.makePDFForExport() }
                
                Button("Clear") {
                    homeViewModel.clear()
                }
            }
            .padding()

            Text(homeViewModel.status)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal)

            WebViewContainer(webView: homeViewModel.webPage)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fileExporter(
            isPresented: $homeViewModel.isExporting,
            
            document: homeViewModel.exportData.map {
                PDFFileDocument(data: $0)
            },
            
            contentType: .pdf,
            defaultFilename: homeViewModel.suggestedFileName()
        ) { result in
            
            switch result {
            
            case .success(let url):
                homeViewModel.status = "Saved: \(url.path)"
            
            case .failure(let error):
                homeViewModel.status =
                    "Save failed: \(error.localizedDescription)"
            }

            homeViewModel.exportDocument = nil
        }
    }
}

#Preview {
    HomeView()
}
