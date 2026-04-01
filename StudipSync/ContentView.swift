import SwiftUI

struct ContentView: View {
    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("StudipSync")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Status: \(statusController.syncState.statusText)")
                .font(.headline)

            HStack {
                Button("Jetzt synchronisieren") {
                    syncScheduler.triggerManualSync()
                }

                SettingsLink {
                    Text("Einstellungen öffnen")
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 560, minHeight: 320)
    }
}

#Preview {
    let container = AppContainer()
    ContentView(
        statusController: container.statusController,
        syncScheduler: container.syncScheduler
    )
}
