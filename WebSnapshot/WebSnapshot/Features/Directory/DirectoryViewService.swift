import Foundation
import SwiftData

struct DirectoryGroup: Identifiable {

    init(_ directoryURL: URL,_ directoryHistoryURL: URL?,_ files: [Directory]) {
        self.directoryURL = directoryURL
        self.directoryHistoryURL = directoryHistoryURL
        self.files = files
    }
    
    let directoryURL: URL

    let directoryHistoryURL: URL?

    let files: [Directory]

    var id: String {
        return "\(canUnset ? "history" : "files"):\(directoryURL.standardizedFileURL.path)"
    }

    var canUnset: Bool {
        directoryHistoryURL != nil
    }
    
    var directoryName: String {
        let name = directoryURL.lastPathComponent

        return name.isEmpty ? directoryURL.path : name
    }

}

enum DirectoryViewService {

    static func hasSavedItems(_ directoryHistories: [DirectoryHistory]) -> Bool {
        directoryHistories.isEmpty == false
    }

    static func fileExists(_ url: URL) -> Bool {
        isExistingFile(url)
    }
    
    @MainActor
    static func groupedDirectories(_ directories: [Directory], _ directoryHistories: [DirectoryHistory], _ searchText: String ) -> [DirectoryGroup] {
        let groupedFiles = Dictionary(grouping: filteredDirectories(directories.filter{
            directory in
            isExistingFile(directory)
        }, searchText )){
            directory in
            directory.resolvedURL.deletingLastPathComponent().standardizedFileURL
        }

        return directoryHistories.compactMap {

            directoryHistory -> DirectoryGroup? in

            let directoryURL = directoryHistory.resolvedURL.standardizedFileURL

            let files = groupedFiles[directoryURL] ?? []

            guard shouldIncludeDirectoryGroup(directoryURL, files, searchText ) else {
                return nil
            }

            return DirectoryGroup( directoryURL,  directoryHistory.url,  files.sorted {fileSort($0, $1) })
        }
        .sorted {
            lhs, rhs in lhs.directoryURL.path.localizedStandardCompare(rhs.directoryURL.path) == .orderedAscending
        }
    }
    
    @MainActor
    static func delete(_ directory: Directory, _ modelContext: ModelContext) throws {
        let fileURL = directory.resolvedURL

        defer {
            if fileURL.startAccessingSecurityScopedResource() {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }

        try DirectoryService.delete(directory.url, modelContext)
    }
    
    @MainActor
    static func unset(_ directoryGroup: DirectoryGroup, _ modelContext: ModelContext) throws {
        guard let directoryHistoryURL = directoryGroup.directoryHistoryURL else {
            return
        }

        try DirectoryHistoryService.unset(directoryHistoryURL, modelContext)
    }

    @MainActor
    private static func filteredDirectories(_ directories: [Directory], _ searchText: String) -> [Directory] {
        guard searchText.isEmpty == false else {
            return directories.sorted {
                fileSort($0, $1)
            }
        }

        let query = searchText.localizedLowercase

        return directories.filter {
            directory in
            let url = directory.resolvedURL

            return url.lastPathComponent.localizedLowercase.contains(query)
            || url.path.localizedLowercase.contains(query)
            || url.deletingLastPathComponent().path.localizedLowercase.contains(query)
        }
        .sorted {
            fileSort($0, $1)
        }
    }

    @MainActor
    private static func fileSort(_ lhs: Directory, _ rhs: Directory) -> Bool {
        lhs.resolvedURL.lastPathComponent.localizedStandardCompare(
            rhs.resolvedURL.lastPathComponent
        ) == .orderedAscending
    }
    
    @MainActor
    private static func isExistingFile(_ directory: Directory) -> Bool {
        isExistingFile(directory.resolvedURL)
    }

    
    private static func shouldIncludeDirectoryGroup(_ directoryURL: URL, _ files: [Directory], _ searchText: String) -> Bool {
        guard searchText.isEmpty == false else {
            return true
        }

        return files.isEmpty == false || directoryMatchesSearch(directoryURL, searchText)
    }

    private static func directoryMatchesSearch(_ directoryURL: URL, _ searchText: String ) -> Bool {
        let query = searchText.localizedLowercase

        return directoryURL.lastPathComponent.localizedLowercase.contains(query) || directoryURL.path.localizedLowercase.contains(query)
    }
    
    private static func isExistingFile(_ url: URL) -> Bool {
        defer {
            if url.startAccessingSecurityScopedResource() {
                url.stopAccessingSecurityScopedResource()
            }
        }

        var isDirectory: ObjCBool = false

        return FileManager.default.fileExists(atPath: url.path,isDirectory: &isDirectory) && isDirectory.boolValue == false
    }
    
}
