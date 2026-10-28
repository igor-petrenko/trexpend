import SwiftUI

private enum TransactionPrimaryAlignment: AlignmentID {
    static func defaultValue(in dimensions: ViewDimensions) -> CGFloat { dimensions[VerticalAlignment.center] }
}

private extension VerticalAlignment {
    static let transactionPrimary = VerticalAlignment(TransactionPrimaryAlignment.self)
}

struct TransactionRowView: View {
    let row: HistoryRow
    private var transfer: Bool { row.type == .transfer }
    private var color: Color { transfer ? .accentColor : (row.incoming ? .green : .red) }

    var body: some View {
        HStack(alignment: .transactionPrimary, spacing: 10) {
            CategoryIconView(symbol: transfer ? "arrow.left.arrow.right" : row.symbol, color: color)
                .alignmentGuide(.transactionPrimary) { $0[VerticalAlignment.center] }
            VStack(alignment: .leading, spacing: 4) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(transfer ? ((row.incoming ? "From " : "To ") + (row.counterparty ?? "Account")) : row.category)
                        .font(.body.weight(.medium))
                    Text(String(row.date.storage.suffix(8).prefix(5)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                .alignmentGuide(.transactionPrimary) { $0[VerticalAlignment.center] }
                if transfer { secondary(row.category) }
                if let notes = row.notes, !notes.isEmpty { secondary(notes) }
                if row.fee != 0, let currency = row.feeCurrency, let account = row.feeAccountName {
                    secondary("Fee " + MoneyPresentation.number(row.fee, places: currency.decimalPlaces) + " " + currency.code + " - " + account)
                }
            }
            .lineLimit(1).truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .clipped()
            Text((row.incoming ? "+" : "-") + MoneyPresentation.number(row.amount, places: row.currency.decimalPlaces))
                .font(.callout.weight(.semibold)).monospacedDigit().foregroundStyle(color)
                .lineLimit(1).minimumScaleFactor(0.5).layoutPriority(2)
                .alignmentGuide(.transactionPrimary) { $0[VerticalAlignment.center] }
        }
        .padding(14)
        .accessibilityElement(children: .combine)
    }

    private func secondary(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary)
    }
}
