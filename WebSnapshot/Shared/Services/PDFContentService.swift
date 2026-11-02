import Foundation
import PDFKit
import CoreGraphics

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
        return try await text(data, pageIndex: pageIndex)
    }

    func text(_ data: Data, pageIndex: Int) async throws -> String {
        try Task.checkCancellation()
        
        guard let document = PDFDocument(data: data), !document.isLocked, let page = document.page(at: pageIndex) else {
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

        let pageWidth = swapsDimensions ? pageBounds.height : pageBounds.width

        let pageHeight = swapsDimensions ? pageBounds.width : pageBounds.height

        guard pageWidth.isFinite, pageHeight.isFinite, pageWidth > 0, pageHeight > 0, dpi.isFinite, dpi > 0 else {
            throw AppError.textRecognitionFailed("The PDF page has an invalid image size.")
        }

        let maximumDimension: CGFloat = 8_192

        let maximumPixels: CGFloat = 16_000_000

        var scale = min(dpi / 72, maximumDimension / max(pageWidth, pageHeight))

        let pixels = (pageWidth * scale) * (pageHeight * scale)

        if pixels > maximumPixels {
            scale *= sqrt(maximumPixels / pixels)
        }

        guard scale.isFinite, scale > 0 else {
            throw AppError.textRecognitionFailed("The PDF page has an invalid image size.")
        }

        let width = max(1, Int(floor(pageWidth * scale)))

        let height = max(1, Int(floor(pageHeight * scale)))

        scale = min(CGFloat(width) / pageWidth, CGFloat(height) / pageHeight)

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
