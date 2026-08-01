import SwiftUI
import PDFKit

struct DirectoryPDFView: NSViewRepresentable {
    let url: URL

    @Binding var currentPageIndex: Int
    @Binding var appError: AppError?
    @Binding var errorTitle: String

    init(
        _ url: URL,
        _ currentPageIndex: Binding<Int>,
        _ appError: Binding<AppError?>,
        _ errorTitle: Binding<String>
    ) {
        self.url = url
        _currentPageIndex = currentPageIndex
        _appError = appError
        _errorTitle = errorTitle
    }

    func makeCoordinator() -> Coordinator {
        Coordinator($currentPageIndex, $appError, $errorTitle)
    }

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()

        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical

        NotificationCenter.default.addObserver(context.coordinator,selector: #selector(Coordinator.pageChanged(_:)),name: .PDFViewPageChanged,object: view)

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
                context.coordinator.errorTitle.wrappedValue = "PDF Could Not Be Opened"
                context.coordinator.appError.wrappedValue = appError
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
                context.coordinator.errorTitle.wrappedValue = "PDF Could Not Be Opened"
                context.coordinator.appError.wrappedValue = appError
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
        var currentPageIndex: Binding<Int>
        var appError: Binding<AppError?>
        var errorTitle: Binding<String>
        
        var loadedURL: URL?
        
        var lastPageIndex: Int?

        init(
            _ currentPageIndex: Binding<Int>,
            _ appError: Binding<AppError?>,
            _ errorTitle: Binding<String>
        ) {
            self.currentPageIndex = currentPageIndex
            self.appError = appError
            self.errorTitle = errorTitle
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

                currentPageIndex.wrappedValue = pageIndex
            }
        }
    }
}
