import Foundation

nonisolated enum PDFTagName {
    static func display(_ input: String) -> String {
        input.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func normalized(_ input: String) -> String {
        display(input).precomposedStringWithCanonicalMapping
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased(with: Locale(identifier: "en_US_POSIX"))
    }
}
