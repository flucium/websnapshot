import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext
    
    @EnvironmentObject private var sync: LibrarySyncService
    
    @EnvironmentObject private var contentService: LibraryContentService

    @StateObject private var settingsViewState: SettingsViewState = SettingsViewState()
    
    @Query private var appearanceSettings: [AppearanceSettings]
    
    @Query private var storageSettings: [StorageSettings]

    
    private var syncState: LibrarySyncState { sync.state }
    
    private var contentState: LibraryContentState { contentService.state }

    private var savedAppearance: AppearanceSettings.Appearance {
        AppearanceSettingsService.appearance(appearanceSettings)
    }

    private var savedStorage: StorageSettings.Storage {
        StorageSettingsService.storage(storageSettings)
    }

    private var fixedStoragePath: String? {
        StorageSettingsService.fixedStoragePath(storageSettings)
    }

    private var savedSync: Bool {
        storageSettings.first?.syncEnabled ?? false
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    appearanceView()

                    icloudSyncView()

                    storageView()
                    
                    refreshCacheView()

                }
                .frame(maxWidth: 720)
                
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .disabled(syncState.isSwitching)
        .task(id: savedAppearance) {
            let appearance = savedAppearance
            if settingsViewState.selectedAppearance != appearance {
                settingsViewState.selectedAppearance = appearance
            }
        }
        .task(id: savedStorage) {
            let storage = savedStorage
            if settingsViewState.selectedStorage != storage {
                settingsViewState.selectedStorage = storage
            }
        }
        .task(id: savedSync) {
            if settingsViewState.selectedSync != savedSync {
                settingsViewState.selectedSync = savedSync
            }
        }
        .onChange(of: settingsViewState.selectedSync) { _, enabled in
            
            guard enabled != savedSync else {
                return
            }
            
            Task { @MainActor in
            
                let succeeded = await SettingsViewService.changeSync(settingsViewState, modelContext, enabled, sync: sync)
                
                if !succeeded {
                    settingsViewState.selectedSync = savedSync
                }
                
            }
            
        }
        .onChange(of: settingsViewState.selectedAppearance) {
            _, appearance in
            
            let previousAppearance = savedAppearance
            
            guard appearance != previousAppearance else {
                return
            }

            Task { @MainActor in
                let didSave = SettingsViewService.saveAppearance(settingsViewState, modelContext, appearance)
                
                if !didSave {
                    settingsViewState.selectedAppearance = previousAppearance
                }
            }
        }
        .onChange(of: settingsViewState.selectedStorage) {
            _, storage in
            
            let previousStorage = savedStorage
            
            guard storage != previousStorage else {
                return
            }

            Task { @MainActor in
                let didSave = SettingsViewService.saveStorage(settingsViewState, modelContext, storage, sync: sync)
            
                if !didSave {
                    settingsViewState.selectedStorage = previousStorage
                }
            }
        }
        .alert(item: $settingsViewState.appError) {
            appError in
            AlertModal.show(settingsViewState.errorTitle, appError)
        }
    }
    
  
    @ViewBuilder
    func appearanceView() -> some View{
        HStack(alignment: .top, spacing: 16) {
        
            Image(systemName: "circle.lefthalf.filled")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        
            VStack(alignment: .leading, spacing: 14) {
        
                VStack(alignment: .leading, spacing: 3) {
                    Text("Appearance")
                        .font(.headline)
        
                    Text("Choose how WebSnapshot follows the system theme.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
        
                }
        
                Picker("Appearance", selection: Binding {
                    settingsViewState.selectedAppearance
                } set: { appearance in
                    Task { @MainActor in
                        settingsViewState.selectedAppearance = appearance
                    }
                }) {
        
                    ForEach(AppearanceSettings.Appearance.allCases) {
                        appearance in
                        Text(AppearanceSettingsService.title(appearance))
                            .tag(appearance)
        
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: 1
                )
        }

    }
    
    @ViewBuilder
    func icloudSyncView() -> some View{
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "icloud")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Sync").font(.headline)
                    Text("Keep your PDFs and tags in iCloud Drive/websnapshot.")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text("Allow access to iCloud Drive once. The websnapshot folder is created automatically when Sync turns on.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Picker("Sync", selection: Binding {
                    settingsViewState.selectedSync
                } set: { enabled in
                    Task { @MainActor in
                        settingsViewState.selectedSync = enabled
                    }
                }) {
                    Text("Off").tag(false)
                    Text("On").tag(true)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                if syncState.isSwitching {
                    HStack {
                        ProgressView().controlSize(.small)
                        Text("Copying library…")
                    }.font(.callout).foregroundStyle(.secondary)
                } else if savedSync {
                    Text("Turning Sync off copies PDFs to your previous Fixed folder, or asks for a folder if Storage was Flexibility.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                if let error = syncState.lastError {
                    Text(error.userMessage).font(.callout).foregroundStyle(.secondary)
                }
                if storageSettings.first?.syncDriveBookmarkData != nil || storageSettings.first?.syncFolderBookmarkData != nil {
                    HStack {
                        Button("Reconnect iCloud Drive…") {
                            SettingsViewService.reconnectSync(settingsViewState, modelContext, sync: sync)
                        }
                        if savedSync {
                            Button("Retry Sync") {
                                Task { await sync.refresh(modelContext) }
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
    
    
    @ViewBuilder
    func storageView() -> some View{
        HStack(alignment: .top, spacing: 16) {
            
            Image(systemName: "folder")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 14) {
            
                VStack(alignment: .leading, spacing: 3) {
                
                    Text("Storage")
                        .font(.headline)

                    Text("Always save to one folder or choose a folder for each save.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                
                }

                Picker("Storage", selection: Binding {
                    settingsViewState.selectedStorage
                } set: { storage in
                    Task { @MainActor in
                        settingsViewState.selectedStorage = storage
                    }
                }) {
                    ForEach(StorageSettings.Storage.allCases) { storage in
                
                        Text(StorageSettingsService.title(storage))
                            .tag(storage)
                        
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .disabled(savedSync)

                if settingsViewState.selectedStorage == .fixed {
                    HStack(spacing: 12) {
                        
                        Text(fixedStoragePath ?? "No folder selected")
                            .font(.callout)
                            .foregroundStyle( fixedStoragePath == nil ? .secondary : .primary )
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(fixedStoragePath ?? "Choose a folder for fixed storage.")

                        Spacer(minLength: 8)

                        Button(fixedStoragePath == nil ? "Choose Folder…" : "Change…" ) {
                            SettingsViewService.chooseFixedStorage( settingsViewState, modelContext, fixedStoragePath, sync: sync )
                        }
                        .disabled(savedSync)
                        
                    }
                    .frame(maxWidth: 480)
                }
                
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
        }
    }
    
    @ViewBuilder
    func refreshCacheView() -> some View{
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
                .frame(width: 34, height: 34)
                .background(
                    Color.accentColor.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 8)
                )
        
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Search Cache")
                        .font(.headline)
                    Text(
                        "Rebuild searchable text and remove library entries for PDFs that have been deleted."
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                }
        
                Button("Refresh Cache") {
                    SettingsViewService
                        .refreshContentCache(
                            settingsViewState,
                            modelContext,
                            contentService
                        )
                }
                .disabled(contentState.isRefreshingCache)
        
                if contentState.isRefreshingCache {
                    HStack {
                        ProgressView().controlSize(.small)
                        if contentState.pendingCount > 0 {
                            Text(
                                "Refreshing… (\(contentState.pendingCount) PDFs remaining)"
                            )
                        } else {
                            Text("Refreshing…")
                        }
                    }
                    .font(.callout)
                    .foregroundStyle(.secondary)
                } else if let result = contentState.cacheRefreshResult {
                    Text(
                        "Refreshed \(result.refreshedCount) PDFs. Removed \(result.removedCount) deleted PDFs."
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    if result.unavailableCount > 0 {
                        Text(
                            "Could not refresh: \(result.unavailableCount) PDFs."
                        )
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .stroke(
                    Color(nsColor: .separatorColor).opacity(0.5),
                    lineWidth: 1
                )
        }
    }
}

#Preview {
    let sync = LibrarySyncService()
    let contentService = LibraryContentService(sync: sync)

    SettingsView()
        .environmentObject(contentService)
        .environmentObject(sync)
}
