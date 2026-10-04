import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @StateObject private var settingsViewState: SettingsViewState = SettingsViewState()
    @StateObject private var contentIndexer = LibraryContentIndexer()

    @Query private var appearanceSettings: [AppearanceSettings]
    @Query private var storageSettings: [StorageSettings]

    private var savedAppearance: AppearanceSettings.Appearance {
        AppearanceSettingsService.appearance(appearanceSettings)
    }

    private var savedStorage: StorageSettings.Storage {
        StorageSettingsService.storage(storageSettings)
    }

    private var fixedStoragePath: String? {
        StorageSettingsService.fixedStoragePath(storageSettings)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 16) {
                        
                        Image(systemName: "circle.lefthalf.filled")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 14) {
                        
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Appearance")
                                    .font(.headline)

                                Text("Choose how WebSnapshot follows the system theme.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                
                            }

                            Picker("Appearance", selection: $settingsViewState.selectedAppearance) {
                                
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
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                    }

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

                            Picker("Storage", selection: $settingsViewState.selectedStorage) {
                                ForEach(StorageSettings.Storage.allCases) { storage in
                            
                                    Text(StorageSettingsService.title(storage))
                                        .tag(storage)
                                    
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)

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
                                        SettingsViewService.chooseFixedStorage( settingsViewState, modelContext, fixedStoragePath )
                                    }
                                    
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
                    
                    HStack(alignment: .top, spacing: 16) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.tint)
                            .frame(width: 34, height: 34)
                            .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))

                        VStack(alignment: .leading, spacing: 14) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Search Cache")
                                    .font(.headline)
                                Text("Rebuild searchable text and remove library entries for PDFs that have been deleted.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }

                            Button("Refresh Cache") {
                                SettingsViewService.refreshContentCache(settingsViewState, modelContext, contentIndexer)
                            }
                            .disabled(settingsViewState.isRefreshingCache)

                            if settingsViewState.isRefreshingCache {
                                HStack {
                                    ProgressView().controlSize(.small)
                                    if contentIndexer.pendingCount > 0 {
                                        Text("Refreshing… (\(contentIndexer.pendingCount) PDFs remaining)")
                                    } else {
                                        Text("Refreshing…")
                                    }
                                }
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            } else if let result = settingsViewState.cacheRefreshResult {
                                Text("Refreshed \(result.refreshedCount) PDFs. Removed \(result.removedCount) deleted PDFs.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                                if result.unavailableCount > 0 {
                                    Text("Could not refresh: \(result.unavailableCount) PDFs.")
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
                            .stroke(Color(nsColor: .separatorColor).opacity(0.5), lineWidth: 1)
                    }

                }
                .frame(maxWidth: 720)
                
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onDisappear {
            settingsViewState.cacheRefreshTask?.cancel()
        }
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
                let didSave = SettingsViewService.saveStorage(settingsViewState, modelContext, storage)
            
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
}

#Preview {
    SettingsView()
}
