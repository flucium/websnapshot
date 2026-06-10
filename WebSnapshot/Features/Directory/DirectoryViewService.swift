import Foundation
import SwiftData
import CoreGraphics
import PDFKit

final class DirectoryViewService{
    static func delete(_ modelContext:ModelContext , _ url:URL ,_ resolvedURL:URL) throws {
        try PDFFileService.delete(modelContext, url)
        try FileIO.delete(resolvedURL)
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
            throw AppError.invalidIO(error.localizedDescription)
        }

        guard
            let document = PDFDocument(data: data), let page = document.page(at: pageIndex)
        else {
            throw AppError.notFound("The displayed PDF page was not found.")
        }

        let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

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
            throw AppError.textRecognitionFailed("Failed to create an image of the displayed PDF page.")
        }

        context.setFillColor(CGColor(gray: 1, alpha: 1))
        
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        
        context.saveGState()
        
        context.scaleBy(x: scale, y: scale)
        
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        
        page.draw(with: .cropBox, to: context)
        
        context.restoreGState()

        guard let image = context.makeImage() else {
            throw AppError.textRecognitionFailed("Failed to render the displayed PDF page.")
        }

        return image
    }
}
