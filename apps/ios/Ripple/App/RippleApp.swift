import SwiftUI

@main
struct RippleApp: App {
    @State private var connection = ConnectionStore.load()

    /// Legacy appearance properties keep the system bar materials; full UIBarAppearance objects would replace them.
    init() {
        let foreground = UIColor(Theme.foreground)
        let bar = UINavigationBar.appearance()
        bar.tintColor = foreground
        bar.titleTextAttributes = [.font: UIFont.heading, .foregroundColor: foreground]
        bar.largeTitleTextAttributes = [.font: UIFont.display, .foregroundColor: foreground]
        for state in [UIControl.State.normal, .highlighted, .disabled] {
            UIBarButtonItem.appearance().setTitleTextAttributes([.font: UIFont.heading], for: state)
            UITabBarItem.appearance().setTitleTextAttributes([.font: UIFont.small], for: state)
        }
        UITabBarItem.appearance().setTitleTextAttributes([.font: UIFont.small], for: .selected)
        UITabBar.appearance().tintColor = UIColor(Theme.accent)
        UICollectionView.appearance().backgroundColor = UIColor(Theme.background)
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if let connection {
                    RootScreen(api: PondAPI(connection: connection)) {
                        if connection.baseURL.host() == PondAccount.server.host() {
                            Task { await PondAccount.signOut(token: connection.token) }
                        }
                        ConnectionStore.clear()
                        self.connection = nil
                    }
                    .id(connection.baseURL)
                } else {
                    NavigationStack { AccountScreen { connection = $0 } }
                        .tint(Theme.foreground)
                }
            }
            .font(.text)
            .foregroundStyle(Theme.foreground)
            .tint(Theme.accent)
            .preferredColorScheme(.dark)
        }
    }
}
