//
//  HomeView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/11.
//

import SwiftUI


private enum NavigationDestination: Hashable {
    case single
    case multiple
    case history
}

struct HomeView: View {
    
    @State private var destination: NavigationDestination? = .single
    
    @ViewBuilder
    private func detail(
        for destination: NavigationDestination?
    ) -> some View {
        switch destination {
        case .single:
            EmptyView()
        case .multiple:
            EmptyView()
        case .history:
            EmptyView()
        default:
            EmptyView()
        }
    }

    
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
}

#Preview {
    HomeView()
}
