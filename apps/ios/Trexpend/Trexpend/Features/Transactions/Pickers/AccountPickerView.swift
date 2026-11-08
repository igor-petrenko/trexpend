import SwiftUI

struct AccountPickerView: View {
    let accounts: [EditorAccount]
    let selected: Int64?
    let choose: (Int64) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    var body: some View {
        List {
            ForEach(accounts.filter { search.isEmpty || $0.name.localizedCaseInsensitiveContains(search) || $0.currency.code.localizedCaseInsensitiveContains(search) }) { account in
                Button {
                    choose(account.id); dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(account.name).foregroundStyle(.primary)
                            Text(account.currency.code + (account.isOpen ? "" : " - Closed")).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if account.favorite { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                        if account.id == selected { Image(systemName: "checkmark") }
                    }
                }
            }
        }.navigationTitle("Account").searchable(text: $search)
    }
}
