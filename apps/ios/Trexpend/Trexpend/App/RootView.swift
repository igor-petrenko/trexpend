import SwiftUI

struct RootView: View {
    let dependencies: AppDependencies
    var startsDatabase = true
    private var session: AppSession { dependencies.session }
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedTab: AppTab = .home

    private enum AppTab: Hashable {
        case home, all, settings
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            Tab("Home", systemImage: "house", value: .home) {
                NavigationStack {
                    HomeView(dependencies: dependencies)
                }.id(session.snapshot?.generation)
            }
            Tab("All", systemImage: "list.bullet", value: .all) {
                NavigationStack {
                    AllHistoryView(dependencies: dependencies)
                }.id(session.snapshot?.generation)
            }
            Tab("Settings", systemImage: "gearshape", value: .settings) {
                NavigationStack {
                    SettingsView(dependencies: dependencies)
                }.id(session.snapshot?.generation)
            }
        }
        .task { if startsDatabase { await dependencies.start() } }
        .onChange(of: scenePhase) { _, phase in
            if startsDatabase, phase == .active { Task { await dependencies.start() } }
        }
        .alert("Database unavailable", isPresented: Binding(get: { session.showsStartupFailure }, set: { session.showsStartupFailure = $0 })) {
            Button("Import Database") {
                selectedTab = .settings
                session.recoveryAction = .importDatabase
            }
            Button("Reset Database", role: .destructive) {
                selectedTab = .settings
                session.recoveryAction = .reset
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if case .failed(let message) = session.databaseAvailability { Text(message) }
        }
        .onChange(of: session.snapshot?.generation) { old, new in
            if old != nil, old != new { selectedTab = .home }
        }
    }
}

struct DatabaseUnavailableView: View {
    var body: some View {
        ContentUnavailableView {
            Label {
                Text("No database loaded")
            } icon: {
                Image(.logo)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview("No database") {
    RootView(dependencies: AppDependencies(), startsDatabase: false)
        .preferredColorScheme(.light)
}

#Preview("Large text") {
    RootView(dependencies: AppDependencies(), startsDatabase: false)
        .preferredColorScheme(.light)
        .environment(\.dynamicTypeSize, .accessibility3)
}

struct DatabaseStatusView: View {
    let session: AppSession

    var body: some View {
        switch session.databaseAvailability {
        case .notLoaded:
            DatabaseUnavailableView()
        case .loading:
            ProgressView("Opening database")
        case .ready(let snapshot):
            if snapshot.accountCount == 0 {
                ContentUnavailableView("No accounts", systemImage: "wallet.bifold", description: Text("Import a database in Settings."))
            } else {
                ContentUnavailableView("Database ready", systemImage: "checkmark.circle")
            }
        case .failed(let message):
            ContentUnavailableView("Database unavailable", systemImage: "exclamationmark.triangle", description: Text(message))
        }
    }
}
