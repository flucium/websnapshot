//
//  WebSnapshotApp.swift
//  WebSnapshot
//
//  Created by flucium on 2026/03/06.
//

import SwiftUI
import AppKit


@main
struct WebSnapshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }
}

func updateAppIcon() {
    let appearance = NSApplication.shared.effectiveAppearance
    let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua

    let iconName = isDark ? "IconDark" : "IconLight"

    if let image = NSImage(named: iconName) {
        NSApplication.shared.applicationIconImage = image
    }
}


final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        updateAppIcon()

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("AppleInterfaceThemeChangedNotification"),
            object: nil,
            queue: .main
        ) { _ in
            updateAppIcon()
        }
    }
}
