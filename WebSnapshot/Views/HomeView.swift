//
//  HomeView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import SwiftUI
import WebKit
import SwiftData
import UniformTypeIdentifiers


private enum NavigationDestination: Hashable {
    case single
    case multiple
    case history
}

struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var destination: NavigationDestination? = .single
    @State private var selectedHistoryItem: PDFHistoryEntry? = nil

    @Query private var historyItems: [PDFHistoryEntry]

    var body: some View {
        NavigationSplitView {
            List(
                selection: $destination
            ) {

                NavigationLink(
                    value: NavigationDestination.single
                ) {
                    Label(
                        "Single",
                        systemImage: "magnifyingglass"
                    )
                }
                NavigationLink(
                    value: NavigationDestination.multiple
                ) {
                    Label(
                        "Multiple",
                        systemImage: "magnifyingglass.circle"
                    )
                }
                NavigationLink(
                    value: NavigationDestination.history
                ) {
                    Label(
                        "History",
                        systemImage: "list.bullet.circle"
                    )
                }
            }
        } detail: {
            detail(
                for: destination
            )

        }

    }

    @ViewBuilder
    private func detail(
        for destination: NavigationDestination?
    ) -> some View {
        switch destination {
        case .single:
            SingleView()
        case .multiple:
            MultipleView()
        case .history:
            HistoryView(
                items: historyItems,
                onDelete: { item in
                    deleteHistory(item)
                }
            )
        default:
            EmptyView()
        }
    }

    private func deleteHistory(_ item: PDFHistoryEntry) {
        if selectedHistoryItem?.persistentModelID == item.persistentModelID {
            selectedHistoryItem = nil
        }

        modelContext.delete(item)

        do {
            try modelContext.save()
        } catch {
            print("History delete failed: \(error.localizedDescription)")
        }
    }
}

#Preview {
    HomeView()
}
