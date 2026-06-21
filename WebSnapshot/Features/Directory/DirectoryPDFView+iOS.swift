#if os(iOS)
import SwiftUI
import PDFKit

struct PlatformDirectoryPDFView: UIViewRepresentable {
    let url: URL

    @Binding var currentPageIndex: Int

    func makeCoordinator() -> DirectoryPDFViewCoordinator {
        DirectoryPDFViewCoordinator(currentPageIndex: $currentPageIndex)
    }

    func makeUIView(context: Context) -> PDFView {
        DirectoryPDFViewSupport.makeView(coordinator: context.coordinator)
    }

    func updateUIView(_ view: PDFView, context: Context) {
        DirectoryPDFViewSupport.updateView(
            view,
            url: url,
            coordinator: context.coordinator
        )
    }

    static func dismantleUIView(
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
