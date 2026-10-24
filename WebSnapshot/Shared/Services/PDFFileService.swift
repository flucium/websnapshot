import Foundation
import SwiftData

@MainActor
enum PDFFileService {
    static func register(_ context: ModelContext, _ url: URL) throws {
       
        let bookmark = try URL.securityScopedBookmarkData(url)
        
        let entries = try context.fetch(FetchDescriptor<PDFFile>())
        
        _ = try updateLocations(entries)
        

        if let pdf = entries.first(where: {
            normalizedURL($0.url) == normalizedURL(url)
        }) {
        
            pdf.bookmarkData = bookmark
            
            pdf.searchableText = nil
            
            pdf.contentFingerprint = nil
            
        } else {
            context.insert(PDFFile(url, bookmark, Date()))
        }
    }

    static func entries(_ context: ModelContext, matching url: URL) throws -> [PDFFile] {
        let fileURL = normalizedURL(url)
        
        return try context.fetch(FetchDescriptor<PDFFile>()).filter {
            normalizedURL($0.url) == fileURL
        }
    }

    static func remove(_ pdfs: [PDFFile], _ context: ModelContext) {
        PDFTagService.deleteTagsOrphanedByDeleting(pdfs, context)
        
        for pdf in pdfs {
            context.delete(pdf)
        }
    }

    static func refreshLocations(_ context: ModelContext) throws -> Bool {
        try updateLocations(context.fetch(FetchDescriptor<PDFFile>()))
    }

    static func deleteMissingFiles(_ context: ModelContext, _ pdfs: [PDFFile], _ confirmedDeletedIDs: Set<PersistentIdentifier> = [] ) -> Bool {
        
        let missing = pdfs.filter {
            $0.availability == .missing || (confirmedDeletedIDs.contains($0.persistentModelID) && !FileIO.exists($0.resolvedURL))
        }
        
        remove(missing, context)
        
        return !missing.isEmpty
    }

    private static func updateLocations(_ entries: [PDFFile]) throws -> Bool {
        var changed = false
        
        for entry in entries {
            guard let resolvedURL = try? entry.resolveURL() else {
                continue
            }
        
            let currentURL = resolvedURL.standardizedFileURL
            
            guard entry.url != currentURL else {
                continue
            }
            
            let bookmark = try URL.securityScopedBookmarkData(resolvedURL)
            
            entry.url = currentURL
            
            entry.bookmarkData = bookmark
            
            changed = true
        }
        
        return changed
    }

    private static func normalizedURL(_ url: URL) -> URL {
        let resolvedURL = url.resolvingSymlinksInPath()
        
        return resolvedURL.deletingLastPathComponent().resolvingSymlinksInPath() .appendingPathComponent(resolvedURL.lastPathComponent).standardizedFileURL
    }
}

@MainActor
enum PDFFileStore {
    static func availableURL(_ directory: URL, _ fileName: String) -> URL {
        
        var candidate = directory.appendingPathComponent(fileName)
        var suffix = 2
        
        while FileIO.exists(candidate) {
            candidate = directory.appendingPathComponent(URL.pdfFileName(fileName, nil, " \(suffix)"))
            suffix += 1
        }
        
        return candidate
    }

    static func save(_ data: Data, _ fileName: String, in directory: URL, register: (URL) throws -> Void = { _ in }) throws -> URL {
        let accessing = directory.startAccessingSecurityScopedResource()
        
        defer {
            if accessing {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
        let destination = availableURL(directory, fileName)
        
        try write(data, to: destination, register: register)
        
        return destination
    }

    static func write(_ data: Data, to destination: URL, register: (URL) throws -> Void = { _ in } ) throws {
        let accessing = destination.startAccessingSecurityScopedResource()
        
        defer {
            if accessing {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        
        let previousData = try FileIO.exists(destination) ? Data(contentsOf: destination) : nil
        
        try data.write(to: destination, options: .atomic)
        
        do {
            try register(destination)
        } catch {
            restore(previousData, at: destination)
        
            throw error
        }
    }

    static func copy(_ source: URL, to directory: URL,register: (URL) throws -> Void) throws -> URL {
        
        let destination = availableURL(directory, source.lastPathComponent)
        
        try FileManager.default.copyItem(at: source, to: destination)
        
        do {
            try register(destination)
        
            return destination
        } catch {
            restore(nil, at: destination)
            throw error
        }
    }

    static func export(_ source: URL, to destination: URL) throws {
        guard source.resolvingSymlinksInPath().standardizedFileURL != destination.resolvingSymlinksInPath().standardizedFileURL else {
        
            throw AppError.error("Choose a different location for the exported PDF.")
        }
        
        let accessingSource = source.startAccessingSecurityScopedResource()
        
        let accessingDestination = destination.startAccessingSecurityScopedResource()
        
        defer {
            if accessingSource {
                source.stopAccessingSecurityScopedResource()
            }
            
            if accessingDestination {
                destination.stopAccessingSecurityScopedResource()
            }
        }
        
        try Data(contentsOf: source, options: .mappedIfSafe).write(to: destination, options: .atomic)
    }

    private static func restore(_ data: Data?, at destination: URL) {
        do {
            if let data {
                try data.write(to: destination, options: .atomic)
            } else {
                try FileManager.default.removeItem(at: destination)
            }
        } catch {
            AppLogger.record(AppError(error), "Restore PDF after failed registration", destination)
        }
    }
}
