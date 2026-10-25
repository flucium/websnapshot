import Foundation
import SwiftData
import PDFKit
import CoreGraphics

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

enum PDFTagService {
    nonisolated static func displayName(_ input: String) -> String {
        PDFTagName.display(input)
    }

    nonisolated static func normalizedName(_ input: String) -> String {
        PDFTagName.normalized(input)
    }

    static func tagNames(_ tags: [PDFTag]) -> [String] {
        sortedTagNames(tags.map(\.name))
    }

    static func addingTag(_ input: String, _ tagNames: [String]) -> [String] {
        let name = displayName(input)

        guard name.isEmpty == false, containsTag(name, tagNames) == false else {
            return tagNames
        }

        return sortedTagNames(tagNames + [name])
    }

    static func togglingTag(_ name: String, _ tagNames: [String]) -> [String] {
        if containsTag(name, tagNames) {
            return removingTag(name, tagNames)
        }

        return addingTag(name, tagNames)
    }

    static func removingTag(_ name: String, _ tagNames: [String]) -> [String] {

        let targetNormalizedName = normalizedName(name)

        return tagNames.filter {
            normalizedName($0) != targetNormalizedName
        }
    }

    static func containsTag(_ name: String, _ tagNames: [String]) -> Bool {
        let targetNormalizedName = normalizedName(name)

        return tagNames.contains {
            normalizedName($0) == targetNormalizedName
        }
    }

    static func replaceTags(_ names: [String], _ pdfFile: PDFFile, _ modelContext: ModelContext) throws {
        var storedTags = try tagsByName(modelContext)

        let selectedTags = resolveTags(names, modelContext, &storedTags)

        let selectedNames = Set(selectedTags.map(\.normalizedName))

        let orphanedTags = pdfFile.tags.filter {
            tag in

            selectedNames.contains(tag.normalizedName) == false && tag.pdfFiles.allSatisfy {
                $0 === pdfFile
            }

        }

        pdfFile.tags = selectedTags

        for tag in orphanedTags {
            modelContext.delete(tag)
        }

    }

    static func tagsByName(_ modelContext: ModelContext) throws -> [String: PDFTag] {
        Dictionary(try modelContext.fetch(FetchDescriptor<PDFTag>()).map {
            ($0.normalizedName, $0)
        }, uniquingKeysWith: {
            first, _ in first
        })
    }

    static func resolveTags(_ names: [String], _ modelContext: ModelContext, _ storedTags: inout [String: PDFTag]) -> [PDFTag] {
        uniqueTags(names).map {
            requestedTag in

            if let storedTag = storedTags[requestedTag.normalizedName] {
                return storedTag
            }

            let tag = PDFTag(requestedTag.name, normalizedName: requestedTag.normalizedName)

            modelContext.insert(tag)

            storedTags[requestedTag.normalizedName] = tag

            return tag
        }
        .sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    static func deleteTagsOrphanedByDeleting(_ pdfFiles: [PDFFile], _ modelContext: ModelContext) {

        let deletedPDFFileIDs = Set(pdfFiles.map(\.persistentModelID))

        var tagsByID: [PersistentIdentifier: PDFTag] = [:]

        for tag in pdfFiles.flatMap(\.tags) {

            tagsByID[tag.persistentModelID] = tag

        }

        for tag in tagsByID.values
        where tag.pdfFiles.allSatisfy({

            deletedPDFFileIDs.contains($0.persistentModelID)

        }) {

            modelContext.delete(tag)

        }

    }

    private static func uniqueTags(_ names: [String]) -> [(name: String, normalizedName: String)] {

        var encounteredNames = Set<String>()

        return names.compactMap {

            input in

            let name = displayName(input)

            let normalizedName = normalizedName(name)

            guard normalizedName.isEmpty == false, encounteredNames.insert(normalizedName).inserted else {
                return nil
            }

            return (name, normalizedName)
        }
    }

    private static func sortedTagNames(_ tagNames: [String]) -> [String] {
        tagNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}


actor PDFContentService {

    private let recognize: @Sendable (CGImage) async throws -> String

    init(_ recognize: @escaping @Sendable (CGImage) async throws -> String = {
            try await OCR.recognizeText($0)
    }
    ) {
        self.recognize = recognize
    }

    func text(_ url: URL) async throws -> String {
        let isAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        try Task.checkCancellation()

        guard let document = PDFDocument(data: try Data(contentsOf: url)), !document.isLocked, document.pageCount > 0 else {
            throw AppError.invalidFileType("The PDF could not be read for content search.")
        }

        var pages: [String] = []

        for index in 0..<document.pageCount {
            try Task.checkCancellation()

            guard let page = document.page(at: index) else {
                throw AppError.notFound("A PDF page could not be read for content search.")
            }

            pages.append(try await text(page))
        }

        try Task.checkCancellation()

        return pages.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func text(_ url: URL, pageIndex: Int) async throws -> String {
        
        let accessing = url.startAccessingSecurityScopedResource()
        
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        try Task.checkCancellation()
        
        let data: Data
        
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppError(error)
        }
        
        
        guard let document = PDFDocument(data: data), let page = document.page(at: pageIndex) else {
            throw AppError.notFound("The displayed PDF page was not found.")
        }
        
        return try await text(page).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func text(_ page: PDFPage) async throws -> String {
        
        try Task.checkCancellation()
        
        let embedded = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        
        if !embedded.isEmpty {
            return embedded
        }
        
        let recognized = try await recognize(Self.render(page, 300))
        
        try Task.checkCancellation()
        
        return recognized
    }

    nonisolated static func fingerprint(_ url: URL) throws -> String {
        let isAccessing = url.startAccessingSecurityScopedResource()

        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)

        guard let modified = attributes[.modificationDate] as? Date, let size = attributes[.size] as? NSNumber, let inode = attributes[.systemFileNumber] as? NSNumber else {

            throw AppError.invalidIO("The PDF's content search information could not be read.")
        }

        return "1:\(modified.timeIntervalSince1970):\(size):\(inode)"
    }

    nonisolated static func render(_ page: PDFPage, _ dpi: CGFloat) throws -> CGImage {

        let pageBounds = page.bounds(for: .cropBox)

        let rotation = (page.rotation % 360 + 360) % 360

        let swapsDimensions = rotation == 90 || rotation == 270

        let scale = dpi / 72

        let width = Int(ceil((swapsDimensions ? pageBounds.height : pageBounds.width) * scale))

        let height = Int(ceil((swapsDimensions ? pageBounds.width : pageBounds.height) * scale))

        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue )else {
            
            throw AppError.textRecognitionFailed("An image could not be created from this PDF page.")
            
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))

        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.saveGState()

        context.scaleBy(x: scale, y: scale)

        page.draw(with: .cropBox, to: context)

        context.restoreGState()

        guard let image = context.makeImage() else {
            throw AppError.textRecognitionFailed("This PDF page could not be prepared for text recognition.")
        }
        
        return image
    }
}
