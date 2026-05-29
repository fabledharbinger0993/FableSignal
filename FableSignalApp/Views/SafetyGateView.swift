import SwiftUI

/// Blocking photosensitive-epilepsy gate. Must be cleared before any session with light can start.
/// Re-shown whenever the user resets the acknowledgment in Settings.
/// Gate is a Congress Moment — do not weaken or bypass.
struct SafetyGateView: View {
    @EnvironmentObject var appState: AppState
    @State private var confirmed = false

    var body: some View {
        ScrollView {
            VStack(spacing: 28) {
                Spacer(minLength: 20)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 52))
                    .foregroundStyle(.orange)

                Text("Safety Information")
                    .font(.title2).bold()
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 14) {
                    Text("FableSignal uses rhythmic flashing light (strobe) and binaural audio.")
                        .fixedSize(horizontal: false, vertical: true)

                    Text("**Do not use this app if you:**")

                    VStack(alignment: .leading, spacing: 8) {
                        BulletRow("Have photosensitive epilepsy or a history of light-triggered seizures")
                        BulletRow("Have been diagnosed with epilepsy or a seizure disorder")
                        BulletRow("Have experienced unexplained blackouts, convulsions, or loss of awareness")
                        BulletRow("Have a family history of photosensitive epilepsy")
                    }
                    .foregroundStyle(.secondary)

                    Text("Stop immediately if you feel dizzy, see visual disturbances, or feel unwell.")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This app is not a medical device. Effects described in research literature are not guaranteed for any individual.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // Explicit acknowledgment — required to proceed.
                HStack(alignment: .top, spacing: 12) {
                    Button {
                        confirmed.toggle()
                    } label: {
                        Image(systemName: confirmed ? "checkmark.square.fill" : "square")
                            .font(.title2)
                            .foregroundStyle(confirmed ? Color.accentColor : .secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(confirmed ? "Confirmed" : "Not confirmed")

                    Text("I have read the above warning. I do not have photosensitive epilepsy or a seizure disorder, and I accept responsibility for my use of this app.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 4)

                Button("I Understand — Enter App") {
                    appState.acknowledgeGate()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!confirmed)

                Spacer(minLength: 20)
            }
            .padding(.horizontal, 24)
        }
    }
}

private struct BulletRow: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•").padding(.top, 1)
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
