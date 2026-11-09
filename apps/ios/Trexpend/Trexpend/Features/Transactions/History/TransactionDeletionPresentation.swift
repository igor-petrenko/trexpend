import SwiftUI

private struct TransactionDeletionPresentation: ViewModifier {
    let state: TransactionDeletionState
    let dependencies: AppDependencies
    func body(content: Content) -> some View {
        @Bindable var state = state
        content.alert(state.target == nil ? "Could not delete transaction" : "Delete transaction?", isPresented: $state.showsAlert) {
            if state.target != nil {
                Button("Delete", role: .destructive) {
                    Task { await state.confirm(database: dependencies.database, session: dependencies.session, settings: dependencies.settings) }
                }
                Button("Cancel", role: .cancel) { state.cancel() }
            } else {
                Button("OK", role: .cancel) { state.cancel() }
            }
        } message: {
            Text(state.error ?? "This permanently deletes the saved transaction, including any transfer fee. Unsaved changes will be discarded.")
        }
        .onChange(of: dependencies.session.snapshot?.generation) { _, _ in state.cancel() }
    }
}

extension View {
    func transactionDeletion(state: TransactionDeletionState, dependencies: AppDependencies) -> some View {
        modifier(TransactionDeletionPresentation(state: state, dependencies: dependencies))
    }
}
