import Foundation
import SwiftData

@MainActor
enum SnapshotHistoryService {
    struct Version {
        let pdfFile: PDFFile
        let number: Int
        let isLatest: Bool
    }

    static func versions(_ pdfFile: PDFFile, _ pdfFiles: [PDFFile]) -> [Version] {
        guard let sourceURL = pdfFile.sourceURL else {
            return [Version(pdfFile: pdfFile, number: 1, isLatest: true)]
        }

        let otherPDFs = pdfFiles.filter {
            $0.sourceURL == sourceURL && $0.persistentModelID != pdfFile.persistentModelID
        }

        let matchingPDFs = ([pdfFile] + otherPDFs).sorted {
            first, second in
            
            let firstDate = first.addedAt ?? .distantPast
            
            let secondDate = second.addedAt ?? .distantPast

            if firstDate == secondDate {
                return first.url.absoluteString < second.url.absoluteString
            }

            return firstDate > secondDate
        }

        return matchingPDFs.enumerated().map {
            index, pdfFile in
            
            Version(pdfFile: pdfFile, number: matchingPDFs.count - index, isLatest: index == 0)
        }
    }
}
