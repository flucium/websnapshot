import SwiftUI
import PDFKit

struct DirectoryPDFView: View {
    let url: URL

    @Binding var currentPageIndex: Int

    init(_ url: URL, _ currentPageIndex: Binding<Int>) {
        self.url = url
        _currentPageIndex = currentPageIndex
    }

    var body: some View {
        PlatformDirectoryPDFView(
            url: url,
            currentPageIndex: $currentPageIndex
        )
    }
}

@MainActor
enum DirectoryPDFViewSupport {
    static func makeView(
        coordinator: DirectoryPDFViewCoordinator
    ) -> PDFView {
        let view = PDFView()

        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical

        NotificationCenter.default.addObserver(
            coordinator,
            selector: #selector(DirectoryPDFViewCoordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )

        return view
    }

    static func updateView(
        _ view: PDFView,
        url: URL,
        coordinator: DirectoryPDFViewCoordinator
    ) {
        guard coordinator.loadedURL != url else {
            return
        }

        coordinator.loadedURL = url

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

    static func dismantleView(
        _ view: PDFView,
        coordinator: DirectoryPDFViewCoordinator
    ) {
        NotificationCenter.default.removeObserver(
            coordinator,
            name: .PDFViewPageChanged,
            object: view
        )

        view.document = nil
    }
}

@MainActor
final class DirectoryPDFViewCoordinator: NSObject {
    var currentPageIndex: Binding<Int>

    var loadedURL: URL?

    var lastPageIndex: Int?

    init(currentPageIndex: Binding<Int>) {
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
