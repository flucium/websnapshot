import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext

    @Query private var settings: [GeneralSettings]

    @StateObject private var settingsViewState = SettingsViewState()

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: appearanceBinding) {
                    ForEach(Appearance.allCases) {
                        appearance in
                        Text(SettingsViewService.title(appearance))
                            .tag(appearance)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
        .alert(
            "Settings Error",
            isPresented: Binding(
                get: {
                    settingsViewState.error != nil
                },
                set: {
                    isPresented in
                    if isPresented == false {
                        settingsViewState.error = nil
                    }
                }
            )
        ) {
            Button("OK", role: .cancel, action: {})
        } message: {
            Text(settingsViewState.error?.localizedDescription ?? "Unknown error.")
        }
    }

    private var appearanceBinding: Binding<Appearance> {
        Binding(
            get: {
                SettingsViewService.appearance(settings)
            },
            set: {
                appearance in
                save(appearance)
            }
        )
    }
    
    
    private func save(_ appearance: Appearance) {
        do {
            try SettingsViewService.save(appearance, modelContext)
            DispatchQueue.main.async {
                settingsViewState.error = nil
            }
        } catch {
            DispatchQueue.main.async {
                settingsViewState.error = AppError(error)
            }
        }
    }
}


#Preview {
    SettingsView().modelContainer(for: GeneralSettings.self, inMemory: true)
}
