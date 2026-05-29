import SwiftUI
import SessionKit

struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var pendingSession: Session?
    @State private var showPlayer = false
    @State private var startError: String?

    var body: some View {
        List(appState.sessionStore.sessions, id: \.id) { session in
            SessionRow(session: session)
                .contentShape(Rectangle())
                .onTapGesture { pendingSession = session }
        }
        .navigationTitle("FableSignal")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gear")
                }
            }
        }
        .sheet(item: $pendingSession) { session in
            SessionPreviewSheet(session: session) {
                pendingSession = nil
                do {
                    try appState.startSession(session)
                    showPlayer = true
                } catch {
                    startError = error.localizedDescription
                }
            }
        }
        .fullScreenCover(isPresented: $showPlayer) {
            if let s = appState.currentSession {
                SessionPlayerView(session: s)
            }
        }
        .alert("Could Not Start Session", isPresented: Binding(
            get: { startError != nil },
            set: { if !$0 { startError = nil } }
        )) {
            Button("OK", role: .cancel) { startError = nil }
        } message: {
            Text(startError ?? "")
        }
    }
}

// MARK: - Row

private struct SessionRow: View {
    let session: Session

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title).font(.headline)
            HStack {
                Label(intentLabel, systemImage: intentIcon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(durationLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }

    private var intentLabel: String {
        switch session.intent {
        case .openRelax: return "Relax"
        case .alert:     return "Alert"
        case .windDown:  return "Wind Down"
        }
    }

    private var intentIcon: String {
        switch session.intent {
        case .openRelax: return "leaf"
        case .alert:     return "bolt"
        case .windDown:  return "moon"
        }
    }

    private var durationLabel: String {
        let m = session.durationSec / 60
        return "\(m) min"
    }
}

// MARK: - Preview sheet

private struct SessionPreviewSheet: View {
    let session: Session
    let onStart: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 24) {
                Image(systemName: intentIcon)
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)

                Text(session.title)
                    .font(.largeTitle).bold()

                VStack(spacing: 0) {
                    InfoRow(label: "Duration", value: "\(session.durationSec / 60) min")
                    Divider().padding(.leading, 16)
                    InfoRow(
                        label: "Audio",
                        value: appState.audioMode == .engine
                            ? "Binaural + Soundscape"
                            : "Bring Your Own Music"
                    )
                    if session.safety.requiresHeadphones && appState.audioMode == .engine {
                        Divider().padding(.leading, 16)
                        HStack {
                            Label("Headphones required for binaural effect", systemImage: "headphones")
                                .font(.caption)
                                .foregroundStyle(.orange)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                    }
                }
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))

                Text("This session uses rhythmic flashing light. Stop immediately if you feel any discomfort.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button("Begin Session") { onStart() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)

                Spacer()
            }
            .padding()
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var intentIcon: String {
        switch session.intent {
        case .openRelax: return "leaf.fill"
        case .alert:     return "bolt.fill"
        case .windDown:  return "moon.fill"
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).bold()
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
