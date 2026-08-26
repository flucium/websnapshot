import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @StateObject private var settingsViewState: SettingsViewState = SettingsViewState()

    @Query private var appearanceSettings: [AppearanceSettings]
    @Query private var storageSettings: [StorageSettings]

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

                            Picker("Appearance", selection: $settingsViewState.appearance) {
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

                            Picker("Storage", selection: $settingsViewState.storage) {
                                ForEach(StorageSettings.Storage.allCases) { storage in
                                    Text(StorageSettingsService.title(storage))
                                        .tag(storage)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)

                            if settingsViewState.storage == .fixed {
                                HStack(spacing: 12) {
                                    Text(settingsViewState.fixedStoragePath ?? "No folder selected")
                                        .font(.callout)
                                        .foregroundStyle(
                                            settingsViewState.fixedStoragePath == nil
                                                ? .secondary
                                                : .primary
                                        )
                                        .lineLimit(1)
                                        .truncationMode(.middle)
                                        .help(settingsViewState.fixedStoragePath ?? "Choose a folder for fixed storage.")

                                    Spacer(minLength: 8)

                                    Button(
                                        settingsViewState.fixedStoragePath == nil
                                            ? "Choose Folder…"
                                            : "Change…"
                                    ) {
                                        chooseFixedStorage()
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
        .onAppear {
            settingsViewState.appearance = AppearanceSettingsService.appearance(appearanceSettings)
            settingsViewState.storage = StorageSettingsService.storage(storageSettings)
            settingsViewState.fixedStoragePath = StorageSettingsService.fixedStoragePath(storageSettings)
        }
        .onChange(of: settingsViewState.appearance) { _, changedAppearance in
            do {
                try AppearanceSettingsService.save(modelContext, changedAppearance)
                settingsViewState.appError = nil
            } catch {
                guard let appError = AppError.presentable(error) else {
                    return
                }

                AppLogger.record(appError, "Save appearance setting")
                settingsViewState.errorTitle = "Appearance Could Not Be Changed"
                settingsViewState.appError = appError
            }
        }
        .onChange(of: settingsViewState.storage) { _, changedStorage in
            do {
                try StorageSettingsService.save(modelContext, changedStorage)
                settingsViewState.appError = nil
            } catch {
                guard let appError = AppError.presentable(error) else {
                    return
                }

                AppLogger.record(appError, "Save storage setting")
                settingsViewState.errorTitle = "Storage Could Not Be Changed"
                settingsViewState.appError = appError
            }
        }
        .alert(item: $settingsViewState.appError) { appError in
            AlertModal.show(settingsViewState.errorTitle, appError)
        }
    }

    private func chooseFixedStorage() {
        let currentURL = settingsViewState.fixedStoragePath.map {
            URL(fileURLWithPath: $0, isDirectory: true)
        }

        guard let selectedURL = directoryPanel(currentURL) else {
            return
        }

        do {
            try StorageSettingsService.saveFixedStorage(
                modelContext,
                selectedURL
            )
            settingsViewState.storage = .fixed
            settingsViewState.fixedStoragePath = selectedURL.path
            settingsViewState.appError = nil
        } catch {
            guard let appError = AppError.presentable(error) else {
                return
            }

            AppLogger.record(
                appError,
                "Save fixed storage folder",
                selectedURL
            )
            settingsViewState.errorTitle = "Storage Folder Could Not Be Changed"
            settingsViewState.appError = appError
        }
    }
    
}

#Preview {
    SettingsView()
}
