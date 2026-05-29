import SwiftUI
import SessionKit

struct SessionListView: View {
    @EnvironmentObject var appState: AppState
    @State private var pendingSession: Session?
    @State private var showPlayer = false
    @State private var startError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 16) {
                    ForEach(appState.sessionStore.sessions, id: \.id) { session in
                        SessionCard(session: session)
                            .contentShape(RoundedRectangle(cornerRadius: 20))
                            .onTapGesture { pendingSession = session }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .navigationTitle("FableSignal")
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbarBackground(Color.black.opacity(0.85), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
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

// MARK: - Card

private struct SessionCard: View {
    let session: Session

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(accentColor.opacity(0.18))
                    .frame(width: 52, height: 52)
                Image(systemName: intentIcon)
                    .font(.system(size: 22))
                    .foregroundStyle(accentColor)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(session.title)
                    .font(.headline)
                    .foregroundStyle(.white)
                HStack(spacing: 8) {
                    Text(intentLabel)
                        .font(.caption)
                        .foregroundStyle(accentColor.opacity(0.85))
                    Text("·")
                        .foregroundStyle(.white.opacity(0.3))
                    Text(durationLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.25))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(accentColor.opacity(0.18), lineWidth: 1)
        )
    }

    private var accentColor: Color {
        switch session.intent {
        case .openRelax: return Color(hue: 0.65, saturation: 0.7, brightness: 0.85)
        case .alert:     return Color(hue: 0.12, saturation: 0.9, brightness: 0.95)
        case .windDown:  return Color(hue: 0.75, saturation: 0.65, brightness: 0.85)
        }
    }

    private var intentIcon: String {
        switch session.intent {
        case .openRelax: return "leaf.fill"
        case .alert:     return "bolt.fill"
        case .windDown:  return "moon.fill"
        }
    }

    private var intentLabel: String {
        switch session.intent {
        case .openRelax: return "Relax"
        case .alert:     return "Alert"
        case .windDown:  return "Wind Down"
        }
    }

    private var durationLabel: String { "\(session.durationSec / 60) min" }
}

// MARK: - Preview sheet

private struct SessionPreviewSheet: View {
    let session: Session
    let onStart: () -> Void

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    ZStack {
                        Circle()
                            .fill(accentColor.opacity(0.15))
                            .frame(width: 96, height: 96)
                        Image(systemName: intentIcon)
                            .font(.system(size: 44))
                            .foregroundStyle(accentColor)
                    }
                    .padding(.top, 16)

                    Text(session.title)
                        .font(.largeTitle).bold()
                        .foregroundStyle(.white)

                    VStack(spacing: 0) {
                        InfoRow(label: "Duration", value: "\(session.durationSec / 60) min")
                        Divider().overlay(Color.white.opacity(0.1))
                        InfoRow(
                            label: "Audio",
                            value: appState.audioMode == .engine
                                ? "Binaural + Soundscape"
                                : "Bring Your Own Music"
                        )
                        if session.safety.requiresHeadphones && appState.audioMode == .engine {
                            Divider().overlay(Color.white.opacity(0.1))
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
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))

                    Text("This session uses rhythmic flashing light. Stop immediately if you feel any discomfort.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .multilineTextAlignment(.center)

                    Button("Begin Session") { onStart() }
                        .buttonStyle(.borderedProminent)
                        .tint(accentColor)
                        .controlSize(.large)

                    Spacer()
                }
                .padding()
            }
            .preferredColorScheme(.dark)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private var accentColor: Color {
        switch session.intent {
        case .openRelax: return Color(hue: 0.65, saturation: 0.7, brightness: 0.85)
        case .alert:     return Color(hue: 0.12, saturation: 0.9, brightness: 0.95)
        case .windDown:  return Color(hue: 0.75, saturation: 0.65, brightness: 0.85)
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
            Text(label).foregroundStyle(.white.opacity(0.5))
            Spacer()
            Text(value).bold().foregroundStyle(.white)
        }
        .font(.callout)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
