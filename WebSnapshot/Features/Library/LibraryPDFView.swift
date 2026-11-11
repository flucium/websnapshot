import SwiftUI
import PDFKit

struct LibraryPDFView: NSViewRepresentable {
    
    @ObservedObject var libraryViewState: LibraryViewState
    
    let url: URL
    
    init(_ url: URL, _ libraryViewState : LibraryViewState) {
        self.url = url
        self.libraryViewState = libraryViewState
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(libraryViewState)
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
        guard let data = libraryViewState.displayedPDFData, libraryViewState.displayedPDFURL == url else {
            view.document = nil
            return
        }

        let version = libraryViewState.displayedPDFVersion

        guard context.coordinator.loadedVersion != version else {
            return
        }

        context.coordinator.loadedVersion = version

        context.coordinator.lastPageIndex = nil

        let pageIndex = libraryViewState.currentPageIndex

        do {
            let document = try Self.document(data)

            view.document = document

            if let page = document.page(at: min(pageIndex, max(0, document.pageCount - 1))) {
                view.go(to: page)
            }
        } catch {
            view.document = nil

            let appError = AppError(error)
            
            AppLogger.record(appError, "Open PDF", url)

            DispatchQueue.main.async {
                guard context.coordinator.loadedVersion == version, libraryViewState.displayedPDFVersion == version else {
                    return
                }

                context.coordinator.present(appError)
            }
        }
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
        weak var libraryViewState: LibraryViewState?
        
        var loadedVersion: UUID?
        
        var lastPageIndex: Int?

        init(_ libraryState: LibraryViewState) {
            self.libraryViewState = libraryState
        }

        func present(_ appError: AppError) {
            libraryViewState?.errorTitle = "PDF Could Not Be Opened"
            libraryViewState?.appError = appError
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

            let version = loadedVersion

            DispatchQueue.main.async { [weak self] in
                guard let self, loadedVersion == version, libraryViewState?.displayedPDFVersion == version else {
                    return
                }

                libraryViewState?.currentPageIndex = pageIndex
            }
        }
    }
}
