import SwiftUI
import SessionKit

struct SessionPlayerView: View {
    let session: Session

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // UI-only elapsed counter; actual timing lives in SessionRunner.
    @State private var displayElapsed: TimeInterval = 0
    private let displayTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Full-screen tunnel matched to session intent
            TunnelBackground(hue: tunnelHue, speed: tunnelSpeed)

            // Dark veil to keep controls readable
            Color.black.opacity(0.38).ignoresSafeArea()

            VStack {
                modeBadge
                    .padding(.top, 20)

                Spacer()

                timeDisplay

                Spacer()

                controls
                    .padding(.bottom, 48)
            }
            .padding(.horizontal, 32)
        }
        .ignoresSafeArea()
        .onReceive(displayTimer) { _ in
            if appState.runnerState == .running { displayElapsed += 1 }
        }
        .onChange(of: appState.runnerState) { newState in
            if newState == .completed { dismiss() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sub-views

    private var modeBadge: some View {
        Label(modeLabel, systemImage: modeIcon)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.6))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.ultraThinMaterial, in: Capsule())
    }

    private var timeDisplay: some View {
        VStack(spacing: 8) {
            Text(session.title)
                .font(.headline)
                .foregroundStyle(.white.opacity(0.5))
            Text(formatTime(remaining))
                .font(.system(size: 72, weight: .thin, design: .monospaced))
                .foregroundStyle(.white)
            Text("remaining")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.35))
        }
        .padding(32)
        .background(.black.opacity(0.30), in: RoundedRectangle(cornerRadius: 28, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Session progress")
        .accessibilityValue(accessibilityTimeValue)
    }

    private var controls: some View {
        HStack(spacing: 56) {
            Button {
                appState.stopSession()
                dismiss()
            } label: {
                controlIcon("stop.fill", size: 22, circleSize: 56)
            }
            .accessibilityLabel("Stop session")

            Button {
                if appState.runnerState == .running {
                    appState.pauseSession()
                } else if appState.runnerState == .paused {
                    try? appState.resumeSession()
                }
            } label: {
                let icon = appState.runnerState == .running ? "pause.fill" : "play.fill"
                controlIcon(icon, size: 30, circleSize: 72)
            }
            .accessibilityLabel(appState.runnerState == .running ? "Pause session" : "Resume session")
        }
    }

    // MARK: - Helpers

    private func controlIcon(_ name: String, size: CGFloat, circleSize: CGFloat) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: circleSize, height: circleSize)
            .background(.ultraThinMaterial, in: Circle())
    }

    private var remaining: TimeInterval {
        max(0, Double(session.durationSec) - displayElapsed)
    }

    private var tunnelHue: Double {
        switch session.intent {
        case .openRelax: return 0.65
        case .alert:     return 0.12
        case .windDown:  return 0.75
        }
    }

    private var tunnelSpeed: Double {
        switch session.intent {
        case .openRelax: return 0.30
        case .alert:     return 0.60
        case .windDown:  return 0.18
        }
    }

    private var modeLabel: String {
        appState.audioMode == .engine ? "Binaural + Strobe" : "Strobe only"
    }

    private var modeIcon: String {
        appState.audioMode == .engine ? "headphones" : "flashlight.on.fill"
    }

    private func formatTime(_ t: TimeInterval) -> String {
        let m = Int(t) / 60
        let s = Int(t) % 60
        return String(format: "%d:%02d", m, s)
    }

    private var accessibilityTimeValue: String {
        let r = Int(remaining)
        let m = r / 60
        let s = r % 60
        return s == 0 ? "\(m) minutes remaining" : "\(m) minutes \(s) seconds remaining"
    }
}
