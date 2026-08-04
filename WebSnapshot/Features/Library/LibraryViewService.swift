import Foundation
import SwiftData
import CoreGraphics
import PDFKit

final class LibraryViewService{
    static func delete(
        _ modelContext: ModelContext,
        _ url: URL,
        _ resolvedURL: URL,
        _ removeFile: ((URL) throws -> Void)? = nil
    ) throws {
        if let removeFile {
            try removeFile(resolvedURL)
        } else {
            try FileIO.delete(resolvedURL)
        }

        do {
            try PDFFileService.delete(modelContext, url)
        } catch {
            AppLogger.recordDiagnostic(
                "The file was deleted, but its library entry could not be removed. Automatic synchronization will retry the cleanup.",
                "Delete PDF library entry",
                resolvedURL
            )
            throw error
        }
    }

    static func deleteMissingFiles(_ modelContext: ModelContext, _ pdfFiles: [PDFFile]) throws {
        var needsSave = false

        let missingPDFFiles = pdfFiles.filter {
            FileIO.exists($0.url) == false
        }

        PDFTagService.deleteTagsOrphanedByDeleting(
            missingPDFFiles,
            in: modelContext
        )

        for pdfFile in missingPDFFiles {
            modelContext.delete(pdfFile)
            needsSave = true
        }

        if needsSave {
            do {
                try modelContext.save()
            } catch {
                modelContext.rollback()
                throw AppError.system(
                    "The library could not be synchronized.",
                    error.localizedDescription,
                    error
                )
            }
        }
    }

    static func matches(
        _ pdfFile: PDFFile,
        _ searchText: String,
        _ mode: SearchMode
    ) -> Bool {
        let searchText = searchText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard searchText.isEmpty == false else {
            return true
        }

        let titleMatches = pdfFile.url.lastPathComponent.localizedCaseInsensitiveContains(searchText)
        let tagMatches = pdfFile.tags.contains {
            $0.name.localizedCaseInsensitiveContains(searchText)
        }

        return switch mode {
        case .all:
            titleMatches || tagMatches
        case .title:
            titleMatches
        case .tag:
            tagMatches
        }
    }

    nonisolated static func textForTranslation(_ url: URL,_ pageIndex: Int ) async throws -> String {
        let isAccessing = url.startAccessingSecurityScopedResource()
        
        defer {
            if isAccessing {
                url.stopAccessingSecurityScopedResource()
            }
        }

        let data: Data
        
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw AppError(error)
        }

        guard
            let document = PDFDocument(data: data), let page = document.page(at: pageIndex)
        else {
            throw AppError.notFound("The displayed PDF page was not found.")
        }

        let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? String()

        if embeddedText.isEmpty == false {
            return embeddedText
        }

        let image = try render(page, 300)
        
        let recognizedText = try await OCR.recognizeText(image).trimmingCharacters(in: .whitespacesAndNewlines)

        guard recognizedText.isEmpty == false else {
            throw AppError.textRecognitionFailed("No text was found on the displayed PDF page.")
        }

        return recognizedText
    }

    nonisolated private static func render(_ page: PDFPage, _ dpi: CGFloat) throws -> CGImage {
        let pageBounds = page.bounds(for: .cropBox)
        
        let scale = dpi / 72
        
        let width = Int(ceil(pageBounds.width * scale))
        
        let height = Int(ceil(pageBounds.height * scale))

        guard
            width > 0, height > 0,
            let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue )
        else {
            throw AppError.textRecognitionFailed("An image could not be created from this PDF page.")
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        context.saveGState()
        
        context.scaleBy(x: scale, y: scale)
        
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        
        page.draw(with: .cropBox, to: context)
        
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw AppError.textRecognitionFailed("This PDF page could not be prepared for text recognition.")
        }

        return image
    }
}
