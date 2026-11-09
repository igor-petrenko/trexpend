import SwiftUI

struct AccountAvatar: View {
    let type: HomeAccountType
    let appearance: AccountAppearance
    var database: DatabaseStore? = nil
    var generation: UUID? = nil
    var preview: Data? = nil
    @State private var image: UIImage?

    private struct Key: Equatable { let id: Int64?; let generation: UUID?; let preview: Data? }
    private var key: Key { Key(id: appearance.customImageID, generation: generation, preview: preview) }
    var body: some View {
        Group {
            if let image { Image(uiImage: image).resizable().scaledToFit() }
            else { Image(systemName: appearance.symbol ?? type.symbol).font(.title3).foregroundStyle(tint) }
        }
        .frame(width: 40, height: 40)
        .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityHidden(true)
        .task(id: key) {
            image = nil
            if let preview { image = UIImage(data: preview); return }
            guard let database, let generation, let id = appearance.customImageID else { return }
            do {
                let data = try await database.customAccountImage(id: id, expectedGeneration: generation)
                guard !Task.isCancelled else { return }
                if let data { image = UIImage(data: data) }
            } catch { image = nil }
        }
    }
    private var tint: Color {
        if let hex = appearance.color, let color = Color.accountHex(hex) { return color }
        return .accentColor
    }
}

extension Color {
    static func accountHex(_ text: String) -> Color? {
        guard text.count == 7, text.first == "#", let value = UInt32(text.dropFirst(), radix: 16) else { return nil }
        return Color(red: Double((value >> 16) & 255) / 255, green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255)
    }
}

struct BankHeading: View {
    let bank: BankInfo?
    var body: some View {
        HStack(spacing: 8) {
            if let asset = bank?.assetName {
                Image(asset).resizable().scaledToFit().frame(width: 28, height: 28)
                    .background(.white, in: RoundedRectangle(cornerRadius: 6)).accessibilityHidden(true)
            }
            Text(bank?.name ?? "No bank")
        }
    }
}
