import SwiftUI
import UIKit

struct CategoryIconView: View {
    let symbol: String?
    let color: Color

    static func resolvedSymbol(_ symbol: String?) -> String {
        guard let symbol, UIImage(systemName: symbol) != nil else { return "square.grid.2x2" }
        return symbol
    }
    var body: some View {
        Image(systemName: Self.resolvedSymbol(symbol)).font(.title3)
            .foregroundStyle(color)
            .frame(width: 40, height: 40)
            .background(color.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityHidden(true)
    }
}
