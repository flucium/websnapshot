//
//  HomeView.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private enum NavigationDestination: Hashable {
    case single
    case multiple
}

struct HomeView: View {
    @State private var destination: NavigationDestination? = .single

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
                        systemImage: "timer"
                    )
                }
                NavigationLink(
                    value: NavigationDestination.multiple
                ) {
                    Label(
                        "Multiple",
                        systemImage: "timer"
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
        default:
            EmptyView()
        }
    }
}


#Preview {
    HomeView()
}
