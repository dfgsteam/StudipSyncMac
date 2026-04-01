import SwiftUI

struct MenuBarRootView: View {
    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(statusController.syncState.statusText)
                .font(.headline)

            Divider()

            Button("Jetzt synchronisieren") {
                syncScheduler.triggerManualSync()
            }

            SettingsLink {
                Text("Einstellungen")
            }

            Divider()

            Button("Beenden") {
                NSApp.terminate(nil)
            }
        }
        .padding(12)
        .frame(width: 280)
    }
}
