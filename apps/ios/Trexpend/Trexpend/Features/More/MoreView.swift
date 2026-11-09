import SwiftUI

struct MoreView: View {
    let dependencies: AppDependencies
    private enum Destination: String, CaseIterable, Identifiable {
        case accounts = "Accounts"
        case categories = "Categories"
        case currencies = "Currencies"

        var id: Self { self }
        var symbol: String {
            switch self {
            case .accounts: "wallet.bifold"
            case .categories: "square.grid.2x2"
            case .currencies: "banknote"
            }
        }
        var description: String {
            switch self {
            case .accounts: "Account management will be added here."
            case .categories: "Category management will be added here."
            case .currencies: "Currency and exchange-rate management will be added here."
            }
        }
    }

    var body: some View {
        List {
            Section("Management") {
                ForEach(Destination.allCases) { destination in
                    NavigationLink(value: destination) {
                        Label(destination.rawValue, systemImage: destination.symbol)
                    }
                }
            }
        }
        .navigationTitle("More")
        .navigationDestination(for: Destination.self) { destination in
            if destination == .accounts { AccountsView(dependencies: dependencies) }
            else { ContentUnavailableView(destination.rawValue, systemImage: destination.symbol,
                                   description: Text(destination.description))
                .navigationTitle(destination.rawValue)
                .navigationBarTitleDisplayMode(.inline) }
        }
    }
}

#Preview {
    NavigationStack { MoreView(dependencies: AppDependencies()) }
        .preferredColorScheme(.light)
}
