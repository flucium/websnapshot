import Foundation
import SwiftData

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
