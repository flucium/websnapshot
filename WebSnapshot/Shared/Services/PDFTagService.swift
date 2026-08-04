import Foundation
import SwiftData

final class PDFTagService {
    static func displayName(_ input: String) -> String {
        input
            .split(whereSeparator: \Character.isWhitespace)
            .joined(separator: " ")
    }

    static func normalizedName(_ input: String) -> String {
        displayName(input)
            .precomposedStringWithCanonicalMapping
            .folding(
                options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }

    static func tagNames(_ tags: [PDFTag]) -> [String] {
        sortedTagNames(tags.map(\.name))
    }

    static func addingTag(_ input: String, to tagNames: [String]) -> [String] {
        let name = displayName(input)

        guard
            name.isEmpty == false,
            containsTag(name, in: tagNames) == false
        else {
            return tagNames
        }

        return sortedTagNames(tagNames + [name])
    }

    static func togglingTag(_ name: String, in tagNames: [String]) -> [String] {
        if containsTag(name, in: tagNames) {
            return removingTag(name, from: tagNames)
        }

        return addingTag(name, to: tagNames)
    }

    static func removingTag(_ name: String, from tagNames: [String]) -> [String] {
        let targetNormalizedName = normalizedName(name)

        return tagNames.filter {
            normalizedName($0) != targetNormalizedName
        }
    }

    static func containsTag(_ name: String, in tagNames: [String]) -> Bool {
        let targetNormalizedName = normalizedName(name)

        return tagNames.contains {
            normalizedName($0) == targetNormalizedName
        }
    }

    static func replaceTags(
        _ names: [String],
        for pdfFile: PDFFile,
        in modelContext: ModelContext
    ) throws {
        let requestedTags = uniqueTags(names)

        do {
            let storedTags = try fetch(modelContext)
            let storedTagsByName = Dictionary(
                storedTags.map { ($0.normalizedName, $0) },
                uniquingKeysWith: { first, _ in first }
            )

            let selectedTags: [PDFTag] = requestedTags.map { requestedTag -> PDFTag in
                if let storedTag = storedTagsByName[requestedTag.normalizedName] {
                    return storedTag
                }

                let tag = PDFTag(
                    requestedTag.name,
                    normalizedName: requestedTag.normalizedName
                )
                modelContext.insert(tag)
                return tag
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }

            let selectedNames = Set(selectedTags.map(\.normalizedName))
            let orphanedTags = pdfFile.tags.filter { tag in
                selectedNames.contains(tag.normalizedName) == false
                    && tag.pdfFiles.allSatisfy { $0 === pdfFile }
            }

            pdfFile.tags = selectedTags

            for tag in orphanedTags {
                modelContext.delete(tag)
            }

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw AppError.system(
                "The tags could not be saved.",
                error.localizedDescription,
                error
            )
        }
    }

    static func deleteTagsOrphanedByDeleting(
        _ pdfFiles: [PDFFile],
        in modelContext: ModelContext
    ) {
        let deletedPDFFileIDs = Set(pdfFiles.map(\.persistentModelID))
        var tagsByID: [PersistentIdentifier: PDFTag] = [:]

        for tag in pdfFiles.flatMap(\.tags) {
            tagsByID[tag.persistentModelID] = tag
        }

        for tag in tagsByID.values where tag.pdfFiles.allSatisfy({
            deletedPDFFileIDs.contains($0.persistentModelID)
        }) {
            modelContext.delete(tag)
        }
    }

    private static func uniqueTags(_ names: [String]) -> [(name: String, normalizedName: String)] {
        var encounteredNames = Set<String>()

        return names.compactMap { input in
            let name = displayName(input)
            let normalizedName = normalizedName(name)

            guard
                normalizedName.isEmpty == false,
                encounteredNames.insert(normalizedName).inserted
            else {
                return nil
            }

            return (name, normalizedName)
        }
    }

    private static func fetch(_ modelContext: ModelContext) throws -> [PDFTag] {
        try modelContext.fetch(FetchDescriptor<PDFTag>())
    }

    private static func sortedTagNames(_ tagNames: [String]) -> [String] {
        tagNames.sorted {
            $0.localizedStandardCompare($1) == .orderedAscending
        }
    }
}
