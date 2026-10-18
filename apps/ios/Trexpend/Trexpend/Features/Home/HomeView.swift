import SwiftUI

struct HomeView: View {
    let session: AppSession

    var body: some View {
        DatabaseStatusView(session: session)
        .navigationTitle("Home")
    }
}

#Preview {
    NavigationStack {
        HomeView(session: AppSession())
    }
    .preferredColorScheme(.light)
}
