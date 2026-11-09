import SwiftUI

struct DefaultAccountPickerView: View {
    let accounts: [EditorAccount]
    let selectedID: Int64?
    let isLoading: Bool
    let isSaving: Bool
    let onSelect: (Int64?) async -> Bool
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [EditorAccount] {
        accounts.filter { $0.isOpen && (search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.currency.code.localizedCaseInsensitiveContains(search)) }
    }
    var body: some View {
        List {
            Button { select(nil) } label: {
                HStack {
                    Text("None")
                    Spacer()
                    if selectedID == nil { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }.disabled(isSaving || isLoading)
            ForEach(filtered) { account in
                Button { select(account.id) } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(account.name)
                            Text(account.currency.code).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        if account.id == selectedID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                    }
                }.disabled(isSaving || isLoading)
            }
        }.tint(.primary)
            .overlay { if isLoading { ProgressView("Loading accounts") } }
            .navigationTitle("Default Account")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Account name or currency")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(isSaving) }
            }
            .interactiveDismissDisabled(isSaving)
    }
    private func select(_ id: Int64?) {
        Task { if await onSelect(id) { dismiss() } }
    }
}
