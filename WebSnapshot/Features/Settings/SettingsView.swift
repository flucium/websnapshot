import SwiftUI
import SwiftData

struct SettingsView: View {

    @Environment(\.modelContext) private var modelContext

    @StateObject private var settingsViewState: SettingsViewState = SettingsViewState()

    @Query private var appearanceSettings: [AppearanceSettings]

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

                    
                }
                .frame(maxWidth: 720)
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            settingsViewState.appearance = AppearanceSettingsService.appearance(appearanceSettings)
        }
        .onChange(of: settingsViewState.appearance) { _, changedAppearance in
            do {
                try AppearanceSettingsService.save(modelContext, changedAppearance)
                settingsViewState.appError = nil
            } catch {
                settingsViewState.appError = AppError(error)
            }
        }
        .alert(item: $settingsViewState.appError) { appError in
            AlertModal.show("Error", appError.localizedDescription)
        }
    }
    
}

#Preview {
    SettingsView()
}
