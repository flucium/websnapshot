//
//  MultipleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//


import SwiftUI
import WebKit
import SwiftData
import UniformTypeIdentifiers

struct MultipleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var multipleViewModel = MultipleViewModel()

    @State private var isExpanded1 = true
    @State private var isExpanded2 = true

    @Query private var historyItems: [PDFFileHistoryEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("Links", isExpanded: $isExpanded1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter one link per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $multipleViewModel.linkText)
                            .frame(height: 140)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.separator, lineWidth: 1)
                            )

                        HStack {
                            Button("Load") {
                                multipleViewModel.load()
                            }

                            Button("Save all PDFs") {
                                multipleViewModel.save()
                            }

                            Button("Clear") {
                                multipleViewModel.clear()
                            }

                            Text(
                                "Valid links: \(multipleViewModel.items.count)"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }

                        Text(multipleViewModel.status)
                            .font(.caption)
                          
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 8)
                }

                DisclosureGroup("Web", isExpanded: $isExpanded2) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(multipleViewModel.items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.url.absoluteString)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(
                                        maxWidth: .infinity,
                                        alignment: .leading
                                    )

                                WebViewContainer(webView: item.webView)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 500)
                                    .clipShape(
                                        RoundedRectangle(cornerRadius: 8)
                                    )
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.top, 8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Spacer(minLength: 0)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .onAppear {
                multipleViewModel.onFileSaved = { url in
                    do {
                        try PDFFileHistoryService.save(
                            url: url,
                            modelContext: modelContext,
                            existingItems: historyItems
                        )
                        multipleViewModel.errorState.clearError()
                    } catch {
                        multipleViewModel.errorState.setError(error)
                        multipleViewModel.status = multipleViewModel.errorState.status
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MultipleView()
}
