import Foundation
import PDFKit
import CoreGraphics

actor PDFContentService {
    
    private let recognize: @Sendable (CGImage) async throws -> String

    init(recognize: @escaping @Sendable (CGImage) async throws -> String = {
        try await OCR.recognizeText($0)}
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

            let embeddedText = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            
            if embeddedText.isEmpty == false {
                pages.append(embeddedText)
            } else {
                let image = try Self.render(page, 300)
            
                pages.append(try await recognize(image))
            }
        }
        
        try Task.checkCancellation()
        
        return pages.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
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

        guard width > 0, height > 0, let colorSpace = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
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
