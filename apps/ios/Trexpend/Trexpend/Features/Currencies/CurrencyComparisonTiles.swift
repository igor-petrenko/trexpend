import SwiftUI

struct CurrencyComparisonTiles: View {
    let currency: CurrencyInfo
    let catalog: CurrencyCatalog
    let amount: Decimal?
    @Environment(\.dynamicTypeSize) private var textSize

    private var targets: [CurrencyInfo] { catalog.comparisons(excluding: currency.id) }
    private var columns: Int { textSize.isAccessibilitySize ? 1 : 2 }

    var body: some View {
        VStack(spacing: 12) {
            if targets.isEmpty { Text("Choose currencies to compare.").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading) }
            ForEach(Array(stride(from: 0, to: targets.count, by: columns)), id: \.self) { start in
                HStack(alignment: .top, spacing: 12) {
                    ForEach(Array(targets.dropFirst(start).prefix(columns))) { target in
                        tile(target).frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
    }

    private func tile(_ target: CurrencyInfo) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(target.code).font(.headline)
                Text(target.name).font(.caption).foregroundStyle(.secondary)
            }
            quote(from: target, to: currency)
            Divider()
            quote(from: currency, to: target)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    private func quote(from: CurrencyInfo, to: CurrencyInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(amount.map(CurrencyConverter.text) ?? "...") \(from.code) =")
                .font(.caption).foregroundStyle(.secondary)
            Text(result(from: from.id, to: to))
                .font(.body.weight(.semibold)).monospacedDigit()
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
    private func result(from: Int64, to: CurrencyInfo) -> String {
        guard let amount else { return "Enter an amount" }
        switch CurrencyComparison.value(amount: amount, from: from, to: to.id, converter: catalog.converter) {
        case .value(let value): return "\(RatePresentation.number(value)) \(to.code)"
        case .unavailable: return "Rate unavailable"
        case .invalid: return "Cannot calculate"
        }
    }
}
