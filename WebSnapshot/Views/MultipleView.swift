//
//  MultipleView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import SwiftUI
import UniformTypeIdentifiers
import WebKit


struct MultipleView: View {

    @StateObject private var homeViewModel = HomeViewModel()

    @State private var isExpanded1 = true
    @State private var isExpanded2 = true

    @State private var linkText: String = ""
    @State private var items: [WebItem] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                DisclosureGroup("Links", isExpanded: $isExpanded1) {
                    VStack(alignment: .leading, spacing: 8) {

                        Text("Enter one link per line")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        TextEditor(text: $linkText)
                            .frame(height: 140)
                            .padding(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(.separator, lineWidth: 1)
                            )

                        HStack {
                            Button("Load") {
                                let urls = parseURLs(from: linkText)
                                items = urls.map { WebItem(url: $0) }
                            }
                            
                            Button("Save all PDFs") {
                                homeViewModel.makePDFsForExport(items: items)
                            }

                            Button("Clear") {
                                linkText = ""
                                items = []
                            }

                           
                            Text("Valid links: \(items.count)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Text(homeViewModel.status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 8)
                }

                DisclosureGroup("Web", isExpanded: $isExpanded2) {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(item.url.absoluteString)
                                    .font(.caption)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                MultipleWebView(webView: item.webView)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 500)
                                    .background(Color.gray.opacity(0.08))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
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
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func parseURLs(from text: String) -> [URL] {
        text
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .compactMap { normalizeURL(from: $0) }
    }

    private func normalizeURL(from string: String) -> URL? {
        if let url = URL(string: string), url.scheme != nil {
            return url
        }

        if let url = URL(string: "https://\(string)") {
            return url
        }

        return nil
    }
}
