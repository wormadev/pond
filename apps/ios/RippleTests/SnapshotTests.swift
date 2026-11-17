import Foundation
import SwiftUI
import Testing
@testable import Ripple

/// The rendered gate: every screen in every state, at three widths and three text sizes.
@MainActor
@Suite(.serialized)
struct SnapshotTests {
    let out = URL(fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_DIR"] ?? NSTemporaryDirectory()).appending(path: "snapshots")

    private func render(_ name: String, _ mode: FixtureProtocol.Mode, @ViewBuilder _ screen: @escaping (LibraryStore) -> some View) async throws {
        let store = LibraryStore(api: FixtureProtocol.api(mode))
        try await SnapshotMatrix.render(name, to: out) {
            NavigationStack { screen(store).containerBackground(Theme.background, for: .navigation) }
                .font(.text)
                .foregroundStyle(Theme.foreground)
                .tint(Theme.foreground)
                .preferredColorScheme(.dark)
        }
    }

    @Test(arguments: [("full", FixtureProtocol.Mode.full), ("worst", .worst), ("empty", .empty), ("failed", .failed), ("loading", .loading)])
    func home(_ name: String, _ mode: FixtureProtocol.Mode) async throws {
        try await render("Home-\(name)", mode) { HomeScreen(store: $0, onSearch: {}) }
    }

    @Test(arguments: [("full", FixtureProtocol.Mode.full), ("worst", .worst), ("empty", .empty), ("failed", .failed), ("loading", .loading)])
    func library(_ name: String, _ mode: FixtureProtocol.Mode) async throws {
        try await render("Library-\(name)", mode) { SavesScreen(store: $0, scope: .all) }
    }

    @Test func collectionWorst() async throws {
        try await render("Collection-worst", .worst) { SavesScreen(store: $0, scope: .tag("interior-design-inspiration-for-the-new-apartment")) }
    }

    @Test func searchIdle() async throws {
        try await render("Search-idle", .full) { store in
            SavesScreen(store: store, scope: .all, isSearch: true).task { await store.refreshSidebar() }
        }
    }

    @Test(arguments: [("full", FixtureProtocol.Mode.full), ("worst", .worst)])
    func detail(_ name: String, _ mode: FixtureProtocol.Mode) async throws {
        try await render("Detail-\(name)", mode) { store in
            SaveDetailScreen(save: Fixtures.save(mode), store: store, list: SavesList(api: store.api, scope: .all))
        }
    }

    @Test(arguments: [("full", FixtureProtocol.Mode.full), ("worst", .worst), ("failed", .failed)])
    func settings(_ name: String, _ mode: FixtureProtocol.Mode) async throws {
        try await render("Settings-\(name)", mode) { store in
            SettingsScreen(store: store, onDisconnect: {}).task { await store.refreshSidebar() }
        }
    }

    @Test(arguments: [("full", FixtureProtocol.Mode.full), ("worst", .worst), ("loading", .loading)])
    func downloads(_ name: String, _ mode: FixtureProtocol.Mode) async throws {
        try await render("Downloads-\(name)", mode) { DownloadsScreen(store: $0) }
    }

    @Test func connect() async throws {
        try await render("Connect", .full) { _ in ConnectScreen { _ in } }
    }
}
