import SwiftUI

struct AllHistoryView: View {
    let session: AppSession

    var body: some View {
        DatabaseStatusView(session: session)
        .navigationTitle("All")
    }
}

#Preview {
    NavigationStack {
        AllHistoryView(session: AppSession())
    }
    .preferredColorScheme(.light)
}
