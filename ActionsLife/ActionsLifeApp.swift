import AppIntents
import SwiftData
import SwiftUI

@main
struct ActionsLifeApp: App {
    @State private var authSession: AuthSession
    private let container: ModelContainer
    private let navigation = AppNavigation()

    init() {
        FirebaseBootstrap.configureIfPossible()
        let container = Persistence.makeContainer()
        self.container = container
        _authSession = State(initialValue: AuthSession(modelContainer: container))
        AppDependencyManager.shared.add(dependency: container)
        AppDependencyManager.shared.add(dependency: navigation)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(authSession)
                .environment(navigation)
                .modelContainer(container)
                .tint(Theme.accent)
                .onOpenURL { url in
                    authSession.handleOpenURL(url)
                }
        }
    }
}
