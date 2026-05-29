import SwiftUI
import SessionRunner

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmResetGate = false

    var body: some View {
        Form {
            audioSection
            safetySection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "Reset Safety Acknowledgment?",
            isPresented: $confirmResetGate,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                appState.resetGateAcknowledgment()
            }
        } message: {
            Text("The safety warning will be shown again before the next session.")
        }
    }

    // MARK: - Sections

    private var audioSection: some View {
        Section {
            Picker("Audio Mode", selection: $appState.audioMode) {
                Text("Binaural + Soundscape").tag(AudioMode.engine)
                Text("Bring Your Own Music").tag(AudioMode.bringYourOwn)
            }
            .disabled(appState.runnerState == .running || appState.runnerState == .paused)

            Group {
                switch appState.audioMode {
                case .engine:
                    Label {
                        Text("App generates binaural tones and ambient soundscape. Headphones required for the binaural effect.")
                    } icon: {
                        Image(systemName: "headphones")
                    }
                case .bringYourOwn:
                    Label {
                        Text("Play your own music via another app. The strobe runs standalone; no headphones required.")
                    } icon: {
                        Image(systemName: "music.note")
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Audio")
        }
    }

    private var safetySection: some View {
        Section {
            Button("Reset Safety Acknowledgment", role: .destructive) {
                confirmResetGate = true
            }
        } header: {
            Text("Safety")
        } footer: {
            Text("Resets the photosensitive epilepsy gate. The warning will be shown again before the next session.")
        }
    }
}
