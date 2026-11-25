import SwiftUI


extension EnvironmentValues {
    @Entry var requestPDFPreview: (@MainActor (PDFPreviewRequest) -> Void)? = nil
}
