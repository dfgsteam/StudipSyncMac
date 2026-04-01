import SwiftUI

struct ContentView: View {
    let statusController: MenuBarStatusController
    let syncScheduler: SyncScheduler
    let semesterSelectionStore: SemesterSelectionStore

    @State private var viewModel: SemesterListViewModel

    init(
        statusController: MenuBarStatusController,
        syncScheduler: SyncScheduler,
        semesterSelectionStore: SemesterSelectionStore,
        repository: StudIPResourceRepository
    ) {
        self.statusController = statusController
        self.syncScheduler = syncScheduler
        self.semesterSelectionStore = semesterSelectionStore
        self._viewModel = State(initialValue: SemesterListViewModel(repository: repository))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("StudipSync")
                .font(.largeTitle)
                .fontWeight(.semibold)

            Text("Status: \(statusController.syncState.statusText)")
                .font(.headline)

            HStack {
                Button("Semester laden") {
                    viewModel.loadSemesters()
                }
                .disabled(viewModel.isLoading)

                Button("Jetzt synchronisieren") {
                    syncScheduler.triggerManualSync()
                }

                SettingsLink {
                    Text("Einstellungen öffnen")
                }
            }

            Text(viewModel.statusMessage)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List(viewModel.semesters) { semester in
                Toggle(isOn: Binding(
                    get: { semesterSelectionStore.isActive(semesterID: semester.id) },
                    set: { semesterSelectionStore.setActive($0, semesterID: semester.id) }
                )) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(semester.title)
                        Text("ID: \(semester.id)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .overlay {
                if viewModel.semesters.isEmpty && !viewModel.isLoading {
                    Text("Noch keine Semester geladen")
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(minWidth: 640, minHeight: 420)
        .task {
            if viewModel.semesters.isEmpty {
                viewModel.loadSemesters()
            }
        }
    }
}

#Preview {
    let container = AppContainer()
    ContentView(
        statusController: container.statusController,
        syncScheduler: container.syncScheduler,
        semesterSelectionStore: container.semesterSelectionStore,
        repository: container.resourceRepository
    )
}
