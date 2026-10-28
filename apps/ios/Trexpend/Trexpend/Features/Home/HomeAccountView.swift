import SwiftUI

struct HomeAccountView: View {
    let account: HomeAccountRow
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .center, spacing: 12) { icon; identity }
                    figures.frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: 12) {
                    icon
                    identity.frame(minWidth: 80)
                    Spacer(minLength: 4)
                    figures.layoutPriority(1)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private var icon: some View {
        Image(systemName: account.type.symbol).font(.title3).foregroundStyle(.tint)
            .frame(width: 40, height: 40)
            .background(Color.accentColor.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(account.name).font(.body.weight(.medium)).lineLimit(2)
                if account.favorite {
                    Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).accessibilityLabel("Favorite")
                }
            }
            if let bank = account.bank, !bank.isEmpty {
                Text(bank).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var figures: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 7) {
            Text(MoneyPresentation.number(account.balance, places: account.currency.decimalPlaces) + " " + account.currency.code)
                .font(.callout.weight(.medium)).monospacedDigit().fixedSize(horizontal: true, vertical: false)
            if account.hasActivity {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) { flow(income: true); flow(income: false) }
                    VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) { flow(income: true); flow(income: false) }
                }
            }
        }
    }
    private func flow(income: Bool) -> some View {
        let value = income ? account.income : account.expenses
        let text = MoneyPresentation.number(value, places: account.currency.decimalPlaces)
        return Label(text, systemImage: income ? "arrow.up.right" : "arrow.down.right")
            .font(.caption).monospacedDigit().foregroundStyle(income ? Color.green : Color.red)
            .fixedSize(horizontal: true, vertical: false)
            .accessibilityLabel((income ? "Income " : "Expenses ") + text + " " + account.currency.code)
    }
}
