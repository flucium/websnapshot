#if os(macOS)
import AppKit
import SwiftUI

@MainActor
enum ApplicationAppearanceUpdater {
    static func update(
        for appearance: AppearanceSettings.Appearance,
        colorScheme: ColorScheme
    ) {
        let applicationAppearance: NSAppearance? = switch appearance {
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        case .system:
            nil
        }

        NSApp.appearance = applicationAppearance

        for window in NSApp.windows {
            window.appearance = applicationAppearance
            window.contentView?.appearance = applicationAppearance
        }

        updateApplicationIcon(for: appearance, colorScheme: colorScheme)
    }

    private static func updateApplicationIcon(
        for appearance: AppearanceSettings.Appearance,
        colorScheme: ColorScheme
    ) {
        let usesDarkIcon = switch appearance {
        case .light:
            false
        case .dark:
            true
        case .system:
            colorScheme == .dark
        }

        let sourceImage: NSImage = usesDarkIcon ? .appIconDark : .appIconLight
        let iconSize = NSSize(width: 128, height: 128)

        let applicationIcon = NSImage(size: iconSize, flipped: false) { _ in
            let iconRect = NSRect(origin: .zero, size: iconSize)
                .insetBy(dx: 12, dy: 12)

            NSBezierPath(
                roundedRect: iconRect,
                xRadius: 23,
                yRadius: 23
            ).addClip()

            sourceImage.draw(in: iconRect)

            return true
        }

        NSApp.applicationIconImage = applicationIcon
    }
}
#endif
