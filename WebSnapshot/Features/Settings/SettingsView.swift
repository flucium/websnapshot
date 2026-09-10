import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @StateObject private var settingsViewState: SettingsViewState = SettingsViewState()

    @State private var selectedAppearance: AppearanceSettings.Appearance = .system
    @State private var selectedStorage: StorageSettings.Storage = .flexibility

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

                            Picker("Appearance", selection: $selectedAppearance) {
                                ForEach(AppearanceSettings.Appearance.allCases) { appearance in
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

                            Picker("Storage", selection: $selectedStorage) {
                                ForEach(StorageSettings.Storage.allCases) { storage in
                                    Text(StorageSettingsService.title(storage))
                                        .tag(storage)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)

                            if selectedStorage == .fixed {
                                HStack(spacing: 12) {
                                    Text(fixedStoragePath ?? "No folder selected")
                                        .font(.callout)
                                        .foregroundStyle(
                                            fixedStoragePath == nil
                                                ? .secondary
                                                : .primary
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(fixedStoragePath ?? "Choose a folder for fixed storage.")

                                    Spacer(minLength: 8)

                                    Button(
                                        fixedStoragePath == nil
                                            ? "Choose Folder…"
                                            : "Change…"
                                    ) {
                                        SettingsViewService.chooseFixedStorage(
                                            settingsViewState,
                                            modelContext,
                                            fixedStoragePath
                                        )
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
                }
                .frame(maxWidth: 720)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onChange(of: savedAppearance, initial: true) { _, appearance in
            
            if selectedAppearance != appearance {
                selectedAppearance = appearance
            }
        }
        .onChange(of: savedStorage, initial: true) { _, storage in
            
            if selectedStorage != storage {
                selectedStorage = storage
            }
        }
        .onChange(of: selectedAppearance) { _, appearance in
            let previousAppearance = savedAppearance
            guard appearance != previousAppearance else { return }

            
            Task { @MainActor in
                let didSave = SettingsViewService.saveAppearance(settingsViewState, modelContext, appearance)
                if !didSave {
                    
                    selectedAppearance = previousAppearance
                }
            }
        }
        .onChange(of: selectedStorage) { _, storage in
            let previousStorage = savedStorage
            guard storage != previousStorage else { return }

            Task { @MainActor in
                let didSave = SettingsViewService.saveStorage(settingsViewState, modelContext, storage)
                if !didSave {
                    
                    selectedStorage = previousStorage
                }
            }
        }
        .alert(item: $settingsViewState.appError) { appError in
            AlertModal.show(settingsViewState.errorTitle, appError)
        }
    }
}

#Preview {
    SettingsView()
}
