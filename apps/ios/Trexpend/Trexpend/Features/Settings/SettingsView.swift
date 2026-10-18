import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    let dependencies: AppDependencies
    @State private var state: SettingsState
    @State private var showsImporter = false
    @State private var showsResetConfirmation = false

    init(dependencies: AppDependencies) {
        self.dependencies = dependencies
        _state = State(initialValue: SettingsState(dependencies: dependencies))
    }

    var body: some View {
        Form {
            Section("Database") {
                if let snapshot = dependencies.session.snapshot {
                    LabeledContent("Display currency", value: snapshot.settings.displayCurrencyCode)
                } else {
                    DatabaseStatusView(session: dependencies.session)
                    if case .failed = dependencies.session.databaseAvailability {
                        Button("Retry") { Task { await dependencies.start() } }
                    }
                }
                Button("Import Database", systemImage: "square.and.arrow.down") { showsImporter = true }
                Button("Save Database Copy", systemImage: "square.and.arrow.up") { Task { await state.exportCopy() } }
                    .disabled(dependencies.session.snapshot == nil)
                Button("Reset Database", systemImage: "arrow.counterclockwise", role: .destructive) { showsResetConfirmation = true }
                if dependencies.session.isBusy { ProgressView("Working") }
            }
            .disabled(dependencies.session.isBusy)
            Section("Automatic Backups") {
                Text("On My iPhone / Trexpend / Backups")
                if let warning = dependencies.session.backupWarning { Text(warning) }
            }
        }
        .navigationTitle("Settings")
        .task { handleRecoveryAction() }
        .onChange(of: dependencies.session.recoveryAction) { _, _ in handleRecoveryAction() }
        .fileImporter(isPresented: $showsImporter, allowedContentTypes: [.data]) { result in
            switch result {
            case .success(let url): state.pendingImport = url
            case .failure(let error):
                if (error as NSError).code != NSUserCancelledError { state.message = DatabaseError.fileAccess.errorDescription }
            }
        }
        .confirmationDialog("Replace Database?", isPresented: Binding(get: { state.pendingImport != nil }, set: { if !$0 { state.pendingImport = nil } }), titleVisibility: .visible) {
            Button("Replace Database", role: .destructive) {
                if let source = state.pendingImport {
                    state.pendingImport = nil
                    Task { await state.importSelected(source: source) }
                }
            }
            Button("Cancel", role: .cancel) { state.pendingImport = nil }
        } message: {
            Text("The imported database will replace all current data and database settings.")
        }
        .confirmationDialog("Reset Database?", isPresented: $showsResetConfirmation, titleVisibility: .visible) {
            Button("Reset Database", role: .destructive) { Task { await state.reset() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All current accounts, transactions, categories, exchange rates, and database settings will be replaced with the initial defaults. You can save a database copy before resetting.")
        }
        .sheet(item: $state.exportRequest, onDismiss: { state.exporterDismissed() }) { request in
            DatabaseExportPicker(url: request.url) { state.finishExport(saved: $0) }
                .interactiveDismissDisabled()
        }
        .alert("Database", isPresented: Binding(get: { state.message != nil }, set: { if !$0 { state.message = nil } })) {
            Button("OK") { state.message = nil }
        } message: { Text(state.message ?? "") }
    }
    private func handleRecoveryAction() {
        guard let action = dependencies.session.recoveryAction else { return }
        dependencies.session.recoveryAction = nil
        switch action {
        case .importDatabase: showsImporter = true
        case .reset: showsResetConfirmation = true
        }
    }

}

#Preview {
    NavigationStack { SettingsView(dependencies: AppDependencies()) }
        .preferredColorScheme(.light)
}
