import SwiftUI

struct AllTransferRowView: View {
    @Environment(\.dynamicTypeSize) private var textSize
    let row: AllHistoryRow
    private var transaction: HistoryRow { row.transaction }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            CategoryIconView(symbol: "arrow.left.arrow.right", color: .accentColor)
            VStack(alignment: .leading, spacing: 10) {
                section(row.source, direction: "From", amount: transaction.amount,
                        sign: "-", color: .red)
                if let destination = row.destination, let received = transaction.counterpartAmount {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.25))
                        .frame(height: 1)
                        .overlay {
                            Image(systemName: "arrow.left.arrow.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(Color.accentColor)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.background, in: Capsule())
                        }
                        .frame(height: 12)
                        .accessibilityHidden(true)
                    section(destination, direction: "To", amount: received,
                            sign: "+", color: .green, includesDetails: true)
                }
            }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private func section(_ account: HistoryAccountContext, direction: String, amount: Decimal,
                         sign: String, color: Color,
                         includesDetails: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(direction + " " + account.name).lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(account.currency.code).fixedSize()
            }
            .font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .transactionPrimary, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(transaction.category).font(.body.weight(.medium))
                        Text(String(transaction.date.storage.suffix(8).prefix(5)))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    .alignmentGuide(.transactionPrimary) { $0[VerticalAlignment.center] }
                    if includesDetails {
                        if let notes = transaction.notes, !notes.isEmpty { secondary(notes) }
                        if transaction.fee != 0, let currency = transaction.feeCurrency,
                           let charged = transaction.feeAccountName {
                            secondary("Fee " + MoneyPresentation.number(transaction.fee, places: currency.decimalPlaces) + " " + currency.code + " - " + charged)
                        }
                    }
                }
                .lineLimit(1).truncationMode(.tail)
                .frame(minWidth: 80, maxWidth: .infinity, alignment: .leading).clipped()
                Text(sign + MoneyPresentation.number(amount, places: account.currency.decimalPlaces))
                    .font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                    .lineLimit(1).minimumScaleFactor(textSize.isAccessibilitySize ? 0.25 : 0.5).layoutPriority(2)
                    .alignmentGuide(.transactionPrimary) { $0[VerticalAlignment.center] }
            }
        }
    }

    private func secondary(_ value: String) -> some View {
        Text(value).font(.caption).foregroundStyle(.secondary)
    }
}
