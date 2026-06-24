import SwiftUI
import PDFKit

struct DirectoryPDFView: NSViewRepresentable {
    let url: URL

    @Binding var currentPageIndex: Int

    init(_ url: URL, _ currentPageIndex: Binding<Int>) {
        self.url = url
        _currentPageIndex = currentPageIndex
    }

    func makeCoordinator() -> Coordinator {
        Coordinator($currentPageIndex)
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

        guard let data = try? Data(contentsOf: url) else {
            view.document = nil
            return
        }

        view.document = PDFDocument(data: data)
    }

    static func dismantleNSView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator, name: .PDFViewPageChanged,object: view)

        view.document = nil
    }

    final class Coordinator: NSObject {
        var currentPageIndex: Binding<Int>
        
        var loadedURL: URL?
        
        var lastPageIndex: Int?

        init(_ currentPageIndex: Binding<Int>) {
            self.currentPageIndex = currentPageIndex
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
