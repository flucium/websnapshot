import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @StateObject private var settingsViewState: SettingsViewState = SettingsViewState()

    @Query private var appearanceSettings: [AppearanceSettings]
    @Query private var storageSettings: [StorageSettings]

    private var appearanceSelection: Binding<AppearanceSettings.Appearance> {
        Binding(
            get: { AppearanceSettingsService.appearance(appearanceSettings) },
            set: saveAppearance
        )
    }

    private var storageSelection: Binding<StorageSettings.Storage> {
        Binding(
            get: { StorageSettingsService.storage(storageSettings) },
            set: saveStorage
        )
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

                            Picker("Appearance", selection: appearanceSelection) {
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

                            Picker("Storage", selection: storageSelection) {
                                ForEach(StorageSettings.Storage.allCases) { storage in
                                    Text(StorageSettingsService.title(storage))
                                        .tag(storage)
                                }
                            }
                            .labelsHidden()
                            .pickerStyle(.segmented)
                            .frame(maxWidth: 360)

                            if storageSelection.wrappedValue == .fixed {
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
        .alert(item: $settingsViewState.appError) { appError in
            AlertModal.show(settingsViewState.errorTitle, appError)
        }
    }

    private func saveAppearance(_ appearance: AppearanceSettings.Appearance) {
        do {
            try AppearanceSettingsService.save(modelContext, appearance)
            settingsViewState.appError = nil
        } catch {
            guard let appError = AppError.presentable(error) else { return }
            AppLogger.record(appError, "Save appearance setting")
            settingsViewState.errorTitle = "Appearance Could Not Be Changed"
            settingsViewState.appError = appError
        }
    }

    private func saveStorage(_ storage: StorageSettings.Storage) {
        do {
            try StorageSettingsService.save(modelContext, storage)
            settingsViewState.appError = nil
        } catch {
            guard let appError = AppError.presentable(error) else { return }
            AppLogger.record(appError, "Save storage setting")
            settingsViewState.errorTitle = "Storage Could Not Be Changed"
            settingsViewState.appError = appError
        }
    }

    private func chooseFixedStorage() {
        let currentURL = fixedStoragePath.map {
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
