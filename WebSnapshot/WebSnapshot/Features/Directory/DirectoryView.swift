import Foundation
import PDFKit
import SwiftData
import SwiftUI

struct DirectoryView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var directories: [Directory]
    
    @Query private var directoryHistories: [DirectoryHistory]

    @StateObject private var directoryViewState = DirectoryViewState()

    @State private var selectedDirectory: Directory?

    var body: some View {
        
        Group {
            if let directory = selectedDirectory {
                selectedFileView(directory)
            } else {
                directoryListView(DirectoryViewService.groupedDirectories(directories, directoryHistories, directoryViewState.searchText))
            }
        }
        .navigationTitle("Directory")
        .alert(
            "Directory Error",
            isPresented: Binding(
                get: {
                    directoryViewState.error != nil
                },
                set: {
                    isPresented in
                    if isPresented == false{
                        directoryViewState.error = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel,action: {}) 
        } message: {
            Text(directoryViewState.error?.localizedDescription ?? "Unknown error.")
        }
    }

    @ViewBuilder
    private func directoryListView(_ directoryGroups: [DirectoryGroup]) -> some View {
        VStack(spacing: 0) {
            if DirectoryViewService.hasSavedItems(directoryHistories) == false{
                
                ContentUnavailableView("No Directory History", systemImage: "folder", description: Text("Saved directories will appear here."))
                
            } else {
                TextField("Search", text: $directoryViewState.searchText)
                    .textFieldStyle(.roundedBorder)
                    .padding()

                if directoryGroups.isEmpty {
                    
                    ContentUnavailableView("No Results",systemImage: "magnifyingglass",description: Text("Try a different search."))
                    
                } else {
                    List {
                        ForEach(directoryGroups) {
                            directoryGroup in
                            Section {
                                directoryGroupRow(directoryGroup)
                                
                                ForEach(directoryGroup.files) {
                                    directory in
                                    directoryRow(directory)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func directoryGroupRow(_ directoryGroup: DirectoryGroup) -> some View {
        if directoryGroup.canUnset {
            directoryGroupContent(directoryGroup)
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    Button("Remove History", role: .destructive) {
                        unset(directoryGroup)
                    }
                }
                .contextMenu {
                    Button("Remove History", role: .destructive) {
                        unset(directoryGroup)
                    }
                }
        } else {
            directoryGroupContent(directoryGroup)
        }
    }
    
    @ViewBuilder
    private func directoryGroupContent(_ directoryGroup: DirectoryGroup) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(directoryGroup.directoryName)
                    .font(.headline)
            }

            Text(directoryGroup.directoryURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
    
    @ViewBuilder
    private func selectedFileView(_ directory: Directory) -> some View {
        VStack(spacing: 8) {
            HStack {
                Button("Back") {
                    selectedDirectory = nil
                }

                Text(directory.resolvedURL.lastPathComponent)
                    .lineLimit(1)

                Spacer()

                Button("Delete", role: .destructive) {
                    delete(directory)
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Group {
                if DirectoryViewService.fileExists( directory.resolvedURL) {
                    DirectoryPDFView( directory.resolvedURL)
                } else {
                    let error = AppError.notFound
                    
                    ContentUnavailableView("Load failed: \(error.errorDescription ?? "unknown")", systemImage: "exclamationmark.triangle", description: Text(directory.resolvedURL.path))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
    
    @ViewBuilder
    private func directoryRow(_ directory: Directory) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(directory.resolvedURL.lastPathComponent)
                .font(.headline)

            Text(directory.resolvedURL.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selectedDirectory = directory
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button("Delete", role: .destructive) {
                delete(directory)
            }
        }
        .contextMenu {
            Button("Open PDF") {
                selectedDirectory = directory
            }

            Button("Delete", role: .destructive) {
                delete(directory)
            }
        }
    }

    private func delete(_ directory: Directory) {
        do {
            try DirectoryViewService.delete(directory, modelContext)

            if selectedDirectory?.persistentModelID == directory.persistentModelID {
                selectedDirectory = nil
            }

            directoryViewState.error = nil
        } catch {
            directoryViewState.error = AppError(error)
        }
    }

    private func unset(_ directoryGroup: DirectoryGroup) {
        do {
            try DirectoryViewService.unset(directoryGroup, modelContext)

            directoryViewState.error = nil
        } catch {
            directoryViewState.error = AppError(error)
        }
    }

}

private struct DirectoryPDFView: NSViewRepresentable {
    let url: URL
    
    init(_ url: URL) {
        self.url = url
    }
    
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        
        view.autoScales = true
        
        view.displayMode = .singlePageContinuous
        
        view.displayDirection = .vertical
        
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        
        defer {
            if url.startAccessingSecurityScopedResource() {
                url.stopAccessingSecurityScopedResource()
            }
        }

        guard let data = try? Data(contentsOf: url) else {
            nsView.document = nil
            return
        }

        nsView.document = PDFDocument(data: data)
    }
}

#Preview {
    DirectoryView()
}
