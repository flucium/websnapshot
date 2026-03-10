//
//  HomeView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/10.
//

import SwiftUI
import SwiftData

private enum NavigationDestination: Hashable {
    case single
    case multiple
    case repository
    case history
}



struct HomeView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var navigationDestination: NavigationDestination? = .single

    @State private var selectedHistoryItem: PDFFileHistoryEntry? = nil

    @Query private var historyItems: [PDFFileHistoryEntry]
    
    var body: some View {
        NavigationSplitView {
            List(
                selection: $navigationDestination
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
                for: navigationDestination
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
        case .repository:
            EmptyView()
        case .history:
            HistoryView(
                items: historyItems,
                onDelete: { item in
                    if selectedHistoryItem?.persistentModelID == item.persistentModelID {
                        selectedHistoryItem = nil
                    }

                    modelContext.delete(item)

                    do {
                        try modelContext.save()
                    } catch {
                        //
                    }
                }
            )
        default:
            EmptyView()
        }
        
        
    }

    
}
#Preview {
    HomeView()
}
