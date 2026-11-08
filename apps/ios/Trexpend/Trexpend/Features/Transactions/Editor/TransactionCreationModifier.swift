import SwiftUI

struct EditorSelection: Identifiable { let id: Int64 }

private struct TransactionCreationModifier: ViewModifier {
    let dependencies: AppDependencies
    let accountID: Int64?
    let enabled: Bool
    @State private var showsCreate = false
    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottomTrailing) {
                if enabled {
                    Button { showsCreate = true } label: {
                        Image(systemName: "plus").font(.title2.weight(.semibold))
                            .frame(width: 64, height: 64)
                    }.buttonStyle(.borderedProminent).buttonBorderShape(.circle)
                        .accessibilityLabel("Create transaction").padding(16)
                }
            }
            .sheet(isPresented: $showsCreate) {
                if let generation = dependencies.session.snapshot?.generation {
                    TransactionEditorView(dependencies: dependencies, generation: generation, accountID: accountID)
                }
            }
    }
}

extension View {
    func transactionCreation(dependencies: AppDependencies, accountID: Int64? = nil, enabled: Bool) -> some View {
        modifier(TransactionCreationModifier(dependencies: dependencies, accountID: accountID, enabled: enabled))
    }
}
