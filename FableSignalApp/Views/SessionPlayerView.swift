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
            Color.black.ignoresSafeArea()

            VStack(spacing: 40) {
                sessionTitle
                progressRing
                modeBadge
                controls
            }
            .padding(.horizontal, 32)
        }
        .onReceive(displayTimer) { _ in
            if appState.runnerState == .running {
                displayElapsed += 1
            }
        }
        .onChange(of: appState.runnerState) { newState in
            if newState == .completed { dismiss() }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Sub-views

    private var sessionTitle: some View {
        Text(session.title)
            .font(.headline)
            .foregroundStyle(.white.opacity(0.6))
    }

    private var progressRing: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.1), lineWidth: 5)
            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Color.white, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: displayElapsed)

            VStack(spacing: 4) {
                Text(formatTime(remaining))
                    .font(.system(size: 52, weight: .thin, design: .monospaced))
                    .foregroundStyle(.white)
                Text("remaining")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
        .frame(width: 230, height: 230)
    }

    private var modeBadge: some View {
        Label(modeLabel, systemImage: modeIcon)
            .font(.caption)
            .foregroundStyle(.white.opacity(0.5))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(.white.opacity(0.08), in: Capsule())
    }

    private var controls: some View {
        HStack(spacing: 56) {
            // Stop
            Button {
                appState.stopSession()
                dismiss()
            } label: {
                controlIcon("stop.fill", size: 22, circleSize: 56, opacity: 0.12)
            }

            // Pause / Resume
            Button {
                if appState.runnerState == .running {
                    appState.pauseSession()
                } else if appState.runnerState == .paused {
                    try? appState.resumeSession()
                }
            } label: {
                let icon = appState.runnerState == .running ? "pause.fill" : "play.fill"
                controlIcon(icon, size: 28, circleSize: 72, opacity: 0.18)
            }
        }
    }

    // MARK: - Helpers

    private func controlIcon(_ name: String, size: CGFloat, circleSize: CGFloat, opacity: Double) -> some View {
        Image(systemName: name)
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(.white)
            .frame(width: circleSize, height: circleSize)
            .background(Color.white.opacity(opacity), in: Circle())
    }

    private var remaining: TimeInterval {
        max(0, Double(session.durationSec) - displayElapsed)
    }

    private var ringProgress: Double {
        guard session.durationSec > 0 else { return 0 }
        return min(1, displayElapsed / Double(session.durationSec))
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
}
