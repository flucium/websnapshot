import Foundation

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
        let accessing = directory.startAccessingSecurityScopedResource()
        
        defer {
            if accessing {
                directory.stopAccessingSecurityScopedResource()
            }
        }
        
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        
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
