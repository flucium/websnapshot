import AppKit
import Combine
import SwiftUI
import SwiftData

@main
struct WebSnapshotApp: App {
    @NSApplicationDelegateAdaptor(WebSnapshotAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(for: MainWindowRequest.self) {
            $request in
            WebSnapshotRootView(libraryStartupService: appDelegate.libraryStartupService, mainWindowRequest: $request, appDelegate: appDelegate )
            .frame(minWidth: 980, minHeight: 400)
        }
        .defaultSize(width: 1000, height: 600)
        .windowResizability(.contentMinSize)
        .commands {
            AppCommands(appDelegate: appDelegate)
        }

        Window("About WebSnapshot", id: AboutView.windowID) {
            AboutView()
        }
        .defaultSize(width: 540, height: 400)
        .windowResizability(.contentMinSize)
        .commandsRemoved()
    }
}

private enum MainWindowRequest: Codable, Hashable {
    case settings
}

private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    
    let appDelegate: WebSnapshotAppDelegate

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About WebSnapshot") {
                openWindow(id: AboutView.windowID)
            }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings") {
                if !appDelegate.showSettingsInExistingWindow() {
                    openWindow(value: MainWindowRequest.settings)
                }
            }
        }
    }
}

private struct AboutView: View {
    static let windowID = "about"

    private enum License: String, CaseIterable {
        case application = "LICENSE"
        case thirdParty = "LICENSE_THIRDPARTY"
    }

    @State private var showLicenses: Bool = false

    @State private var selectedLicense: License = .application

    private var version: String? {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let version, let build, version != build {
            return "\(version) (\(build))"
        }

        return version ?? build
    }

    var body: some View {
        Group {
            if showLicenses {
                licensesView()
            } else {
                aboutView()
            }
        }
        .padding(24)
        .frame(minWidth: 480, maxWidth: .infinity, minHeight: 360, maxHeight: .infinity)
    }

    private func aboutView() -> some View {
        VStack(spacing: 12) {
            // Application icon
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .accessibilityHidden(true)

            // Application name
            Text("WebSnapshot")
                .font(.title)
                .fontWeight(.semibold)

            // Application version
            if let version {
                Text("Version \(version)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Copyright
            if let copyright = Bundle.main.object(forInfoDictionaryKey: "NSHumanReadableCopyright") as? String,
               !copyright.isEmpty {
                TimelineView(.everyMinute) { context in
                    Text(verbatim: copyrightNotice(copyright, on: context.date))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            
            // Author URL
            authorURLView()
            
            // License
            Button("Licenses…") {
                showLicenses = true
            }
        }
    }

    private func copyrightNotice(_ notice: String, on date: Date) -> String {
        let prefix = "Copyright © "
        
        let yearAndHolder = notice.dropFirst(prefix.count)
        
        let currentYear = Calendar(identifier: .gregorian).component(.year, from: date)

        guard notice.hasPrefix(prefix),
                let yearEnd = yearAndHolder.firstIndex(of: " "),
                let startYear = Int(yearAndHolder[..<yearEnd]),
              currentYear > startYear else {
            return notice
        }

        return "\(notice[..<yearEnd])-\(currentYear)\(notice[yearEnd...])"
    }
    
    private func authorURLView() -> some View{
        VStack(alignment: .leading) {
            HStack(spacing: 14){
                // WebSite
                Text("[www.flucium.net](https://www.flucium.net)")
                
                // GitHub
                Text("[github.com/flucium/websnapshot](https://github.com/flucium/websnapshot)")
            }
        }
    }

    
    private func licensesView() -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Button {
                    showLicenses = false
                } label: {
                    Label("Back", systemImage: "chevron.left")
                }

                Text("Licenses")
                    .font(.headline)
            }

            Picker("License", selection: $selectedLicense) {
                ForEach(License.allCases, id: \.self) {
                    license in
                    Text(verbatim: license.rawValue)
                        .tag(license)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)

            ScrollView {
                Group {
                    if let url = Bundle.main.url(forResource: selectedLicense.rawValue, withExtension: nil),
                       let license = try? String(contentsOf: url, encoding: .utf8) {
                        Text(verbatim: license)
                            .textSelection(.enabled)
                    } else {
                        Text("Could not load this license.")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .id(selectedLicense)
        }
    }
}

private struct WebSnapshotRootView: View {
    @ObservedObject var libraryStartupService: LibraryStartupService
    
    @Binding var mainWindowRequest: MainWindowRequest?
    
    @State private var settingsRequested = false
    
    let appDelegate: WebSnapshotAppDelegate
    
    var body: some View {
        Group {
            if let modelContainer = libraryStartupService.modelContainer {
                HomeView(settingsRequested: $settingsRequested)
                    .environmentObject(appDelegate.content)
                    .environmentObject(appDelegate.librarySyncService)
                    .modelContainer(modelContainer)
                
            } else {
                DatabaseRecoveryView(libraryStartupService: libraryStartupService) {
                    Task {
                        await appDelegate.openLibrary()
                    }
                }
            }
        }
        .background {
            MainWindowObserver(settingsRequested: $settingsRequested, onAttach: appDelegate.registerMainWindow)
            .allowsHitTesting(false)
        }
        .onChange(of: mainWindowRequest, initial: true) {
            guard mainWindowRequest == .settings else {
                return
            }
            
            settingsRequested = true
            
            mainWindowRequest = nil
        }
    }
}

private struct MainWindowObserver: NSViewRepresentable {
    let settingsRequested: Binding<Bool>
    
    let onAttach: @MainActor (NSWindow, WindowView) -> Void

    func makeNSView(context: Context) -> WindowView {
        let view = WindowView()
        
        updateNSView(view, context: context)
        
        return view
    }

    func updateNSView(_ windowView: WindowView, context: Context) {
        windowView.settingsRequested = settingsRequested
        
        windowView.onAttach = onAttach
    }

    final class WindowView: NSView {
        var settingsRequested: Binding<Bool> = .constant(false)
        
        var onAttach: (@MainActor (NSWindow, WindowView) -> Void)?

        override func viewDidMoveToWindow() {
            
            super.viewDidMoveToWindow()
            
            if let window {
                onAttach?(window, self)
            }
        }
    }
}

@MainActor
final class WebSnapshotAppDelegate: NSObject, NSApplicationDelegate {
    let libraryStartupService: LibraryStartupService
    
    let librarySyncService: LibrarySyncService
    
    let content: LibraryContentService
    
    let safariRequests: SafariRequestService
    
    private let mainWindowObservers = NSMapTable<NSWindow, MainWindowObserver.WindowView>.weakToWeakObjects()

    private var syncTask: Task<Void, Never>?

    private var appearanceObservation: NSKeyValueObservation?

    private var safariProgressObservation: AnyCancellable?

    private var safariProgressWindow: SafariCaptureProgressWindow?

    
    override convenience init() {
        self.init(LibraryStartupService())
    }

    init(_ libraryStartupService: LibraryStartupService, safariRequests: SafariRequestService? = nil) {
        self.libraryStartupService = libraryStartupService
        
        let librarySyncService = LibrarySyncService()
        
        self.librarySyncService = librarySyncService
        
        content = LibraryContentService( librarySyncService)
        
        self.safariRequests = safariRequests ?? SafariRequestService {
            
            url, context, onStart, onProgress in
            
            try await WebCaptureService.capture(url, context, librarySyncService, chooseDestination: { name in
                prepareForSafariDialog()
                
                return savePanel(name)
                
            }, onProgress: onProgress, onStart)
        }

        super.init()
    }
    

    fileprivate func registerMainWindow(_ window: NSWindow, observer: MainWindowObserver.WindowView) {
        mainWindowObservers.setObject(observer, forKey: window)
    }

    fileprivate func showSettingsInExistingWindow() -> Bool {
        let application = NSApplication.shared
        
        let activeWindows = [application.keyWindow, application.mainWindow].compactMap {
            $0
        }
        
        let windows = activeWindows + application.orderedWindows + application.windows.filter(\.isMiniaturized)

        for window in windows where window.isVisible || window.isMiniaturized {
            
            guard let observer = mainWindowObservers.object(forKey: window) else {
                continue
            }
            
            observer.settingsRequested.wrappedValue = true
            
            if window.isMiniaturized {
                window.deminiaturize(nil)
            }
            
            window.makeKeyAndOrderFront(nil)
            
            return true
        }
        
        return false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {

        safariProgressObservation = safariRequests.$safariRequestState.sink {
            [weak self] _ in

            Task {
                @MainActor [weak self] in

                self?.updateSafariProgress()
            }
        }
       
        Task {
            await openLibrary()
        }
        
        appearanceObservation = NSApp.observe(\.appearance, options: [.initial, .new]) {
            [weak self] _, _ in
            
            Task {
                @MainActor [weak self] in
                
                self?.updateApplicationIcon()
                
            }
            
        }
        
    }

    func openLibrary() async {
        await libraryStartupService.open()

        guard let modelContainer = libraryStartupService.modelContainer else {
            return
        }

        if syncTask == nil {
            syncTask = Task {
                @MainActor in

                while !Task.isCancelled {
                    await librarySyncService.refresh(modelContainer.mainContext)

                    do {
                        try await Task.sleep(for: .seconds(2))
                    } catch {
                        break
                    }
                }
            }
        }

        safariRequests.startProcessing(modelContainer.mainContext)
    }

    func applicationWillTerminate(_ notification: Notification) {
        syncTask?.cancel()
        safariProgressObservation?.cancel()
        safariRequests.cancel()
        safariProgressWindow?.window?.orderOut(nil)
    }

    private func updateSafariProgress() {
        if safariRequests.safariRequestState.current != nil, safariProgressWindow == nil {
            safariProgressWindow = SafariCaptureProgressWindow(safariRequests)
        }

        safariProgressWindow?.update()
    }

   

    func application(_ application: NSApplication, open urls: [URL]) {
        
        let requests = safariRequests
        
        requests.handleFailure = {
            
            error in
        
            prepareForSafariDialog()
            
            let alert = NSAlert()
            
            alert.messageText = "Webpage Could Not Be Saved"
            
            alert.informativeText = error.userMessage
            
            alert.alertStyle = .warning
            
            alert.addButton(withTitle: "Retry")
            
            alert.addButton(withTitle: "Skip")
            
            return alert.runModal() == .alertFirstButtonReturn ? .retry : .skip
        }
        

        for url in urls {
            
            guard (try? SafariCaptureRequest(openURL: url)) != nil else {
                continue
            }
            
            requests.receive(url)
        }
        
        if let modelContainer = libraryStartupService.modelContainer {
            requests.startProcessing(modelContainer.mainContext)
        }
    }
    
    private func updateApplicationIcon() {
        
        guard let applicationAppearance = NSApp.appearance else {
            NSApp.applicationIconImage = nil
            return
        }

        let usesDarkIcon = applicationAppearance.bestMatch( from: [.aqua, .darkAqua]) == .darkAqua
        
        let sourceImage: NSImage = usesDarkIcon ? .appIconDark : .appIconLight
        
        let iconSize = NSSize(width: 128, height: 128)

        let applicationIcon = NSImage(size: iconSize, flipped: false) { _ in
            
            let iconRect = NSRect(origin: .zero, size: iconSize).insetBy(dx: 12, dy: 12)

            NSBezierPath(roundedRect: iconRect, xRadius: 23, yRadius: 23).addClip()
            
            sourceImage.draw(in: iconRect)

            return true
            
        }

        NSApp.applicationIconImage = applicationIcon
    }
    
    deinit {
        appearanceObservation?.invalidate()
        appearanceObservation = nil
    }
}
