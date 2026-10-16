import SwiftUI
import PDFKit

struct LibraryPDFView: NSViewRepresentable {
    
    @ObservedObject var libraryState: LibraryState
    
    let url: URL
    
    init(_ url: URL,_ libraryState: LibraryState) {
        self.url = url
        self.libraryState = libraryState
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(libraryState)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()

        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical

        NotificationCenter.default.addObserver(context.coordinator,selector: #selector(Coordinator.pageChanged(_:)), name: .PDFViewPageChanged,object: view)

        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        guard context.coordinator.loadedURL != url else {
            return
        }

        context.coordinator.loadedURL = url

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
            view.document = nil

            let appError = AppError(error)
            
            AppLogger.record(appError, "Open PDF", url)

            DispatchQueue.main.async {
                context.coordinator.present(appError)
            }
            
            return
        }

        let document: PDFDocument

        do {
            document = try Self.document(data)
        } catch {
            view.document = nil

            let appError = AppError(error)
            
            AppLogger.record(appError, "Open PDF", url)

            DispatchQueue.main.async {
                context.coordinator.present(appError)
            }
            
            return
        }

        view.document = document
    }

    static func document(_ data: Data) throws -> PDFDocument {
        guard let document = PDFDocument(data: data) else {
            throw AppError.invalidFileType("The selected file is not a readable PDF.")
        }

        return document
    }

    static func dismantleNSView(_ view: PDFView, _ coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewPageChanged,object: view)

        view.document = nil
    }

    final class Coordinator: NSObject {
        weak var libraryState: LibraryState?
        
        var loadedURL: URL?
        
        var lastPageIndex: Int?

        init(_ libraryState: LibraryState) {
            self.libraryState = libraryState
        }

        func present(_ appError: AppError) {
            libraryState?.errorTitle = "PDF Could Not Be Opened"
            libraryState?.appError = appError
        }

        @objc func pageChanged(_ notification: Notification) {
            guard
                let pdfView = notification.object as? PDFView,
                let document = pdfView.document,
                let page = pdfView.currentPage
            else {
                return
            }

            let pageIndex = document.index(for: page)

            guard lastPageIndex != pageIndex else {
                return
            }

            lastPageIndex = pageIndex

            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }

                libraryState?.currentPageIndex = pageIndex
            }
        }
    }
}
