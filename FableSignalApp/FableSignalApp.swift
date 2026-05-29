import SwiftUI

@main
struct FableSignalApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
    }
}

private struct RootView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if appState.hasAcknowledgedSafetyGate {
            NavigationStack {
                SessionListView()
            }
        } else {
            SafetyGateView()
        }
    }
}
