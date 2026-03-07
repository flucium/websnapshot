//
//  MultipleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import SwiftUI
import WebKit
import SwiftData
import UniformTypeIdentifiers

struct MultipleView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var viewModel = MultipleViewModel()

    @State private var isExpanded1 = true
    @State private var isExpanded2 = true

    @Query private var historyItems: [PDFHistoryEntry]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                DisclosureGroup("Links", isExpanded: $isExpanded1) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Enter one link per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $viewModel.linkText)
                            .frame(height: 140)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.separator, lineWidth: 1)
                            )

                        HStack {
                            Button("Load") {
                                viewModel.loadLinks()
                            }

                            Button("Save all PDFs") {
                                viewModel.makePDFsForExport()
                            }

                            Button("Clear") {
                                viewModel.clear()
                            }

                            Text("Valid links: \(viewModel.items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(viewModel.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }

                DisclosureGroup("Web", isExpanded: $isExpanded2) {
                    VStack(alignment: .leading, spacing: 16) {
                        ForEach(viewModel.items) { item in
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
                viewModel.onFileSaved = { fileURL in
                    do {
                        try PDFHistoryStore.save(
                            path: fileURL.path,
                            modelContext: modelContext,
                            existingItems: historyItems
                        )
                    } catch {
                        viewModel.status =
                            "History save failed: \(error.localizedDescription)"
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
