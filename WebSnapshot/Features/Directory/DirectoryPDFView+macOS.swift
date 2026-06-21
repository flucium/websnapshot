#if os(macOS)
import SwiftUI
import PDFKit

struct PlatformDirectoryPDFView: NSViewRepresentable {
    let url: URL

    @Binding var currentPageIndex: Int

    func makeCoordinator() -> DirectoryPDFViewCoordinator {
        DirectoryPDFViewCoordinator(currentPageIndex: $currentPageIndex)
    }

    func makeNSView(context: Context) -> PDFView {
        DirectoryPDFViewSupport.makeView(coordinator: context.coordinator)
    }

    func updateNSView(_ view: PDFView, context: Context) {
        DirectoryPDFViewSupport.updateView(
            view,
            url: url,
            coordinator: context.coordinator
        )
    }

    static func dismantleNSView(
        _ view: PDFView,
        coordinator: DirectoryPDFViewCoordinator
    ) {
        DirectoryPDFViewSupport.dismantleView(
            view,
            coordinator: coordinator
        )
    }
}
#endif
