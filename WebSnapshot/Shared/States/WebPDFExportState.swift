import Foundation

@MainActor
struct WebPDFExportState {
    enum Phase: Equatable {
        case preparing
        case resources
        case exporting
    }

    var phase: Phase = .preparing

    var elapsed: TimeInterval = 0

    var height: Double = 0

    var pendingImages = 0

    var waitingForFonts = false

    var title: String {
        switch phase {
        case .preparing:
            "Preparing Page"
        case .resources:
            "Waiting for Images and Fonts"
        case .exporting:
            "Generating PDF"
        }
    }

    var detail: String {
        let time = "\(Int(elapsed)) s elapsed"

        switch phase {
        case .preparing:
            return "Page height: \(Int(height).formatted()) px · \(time)"
        case .resources:
            let fonts = waitingForFonts ? " · Fonts loading" : ""
            return "\(pendingImages) images pending\(fonts) · \(time)"
        case .exporting:
            return "Creating the PDF file…"
        }
    }
}
