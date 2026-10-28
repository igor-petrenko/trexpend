import SwiftUI

struct CurrencyPickerView: View {
    let currencies: [CurrencyInfo]
    let selectedID: Int64?
    let isLoading: Bool
    let isSaving: Bool
    let onSelect: (CurrencyInfo) async -> Bool
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var filtered: [CurrencyInfo] {
        currencies.filter { search.isEmpty || $0.code.localizedCaseInsensitiveContains(search) || $0.name.localizedCaseInsensitiveContains(search) }
    }
    var body: some View {
        List(filtered) { currency in
            Button {
                Task { if await onSelect(currency) { dismiss() } }
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(currency.code).font(.body.weight(.medium))
                        Text(currency.name).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if currency.id == selectedID { Image(systemName: "checkmark").foregroundStyle(.tint) }
                }
            }
            .tint(.primary)
            .disabled(isSaving)
        }
        .overlay {
            if isLoading { ProgressView("Loading currencies") }
            else if filtered.isEmpty { ContentUnavailableView.search(text: search) }
        }
        .navigationTitle("Display Currency")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $search, prompt: "Currency code or name")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() }.disabled(isSaving) }
        }
        .interactiveDismissDisabled(isSaving)
    }
}
