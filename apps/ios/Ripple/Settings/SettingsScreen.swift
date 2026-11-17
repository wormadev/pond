import SwiftUI

struct SettingsScreen: View {
    let store: LibraryStore
    var onDisconnect: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Settings")
                LibraryGroup(store: store)
                ConnectionGroup(store: store, onDisconnect: onDisconnect)
                SectionHeading("Ripple")
                ListRow(title: "Version", icon: "info.circle", value: Self.version)
            }
            .padding(.bottom, Theme.unit * 8)
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .refreshable { await store.refreshSidebar() }
    }

    private static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] ?? "") (\(info?["CFBundleVersion"] ?? ""))"
    }
}

private struct LibraryGroup: View {
    let store: LibraryStore

    var body: some View {
        SectionHeading("Library")
        NavigationLink {
            DownloadsScreen(store: store)
        } label: {
            ListRow(title: "Downloads", icon: "arrow.down.to.line",
                    value: store.info.map { "\($0.counts.ingesting.counted("save")) waiting" },
                    showsChevron: true)
        }
        .buttonStyle(RowPressStyle())
        RowSeparator()
        NavigationLink { LibrariesScreen(store: store) } label: {
            ListRow(title: "Libraries", icon: "books.vertical", value: store.info?.name, showsChevron: true)
        }
        .buttonStyle(RowPressStyle())
        RowSeparator()
        NavigationLink { TagsScreen(store: store) } label: {
            ListRow(title: "Tags", icon: "tag", value: store.tags.count.formatted(), showsChevron: true)
        }
        .buttonStyle(RowPressStyle())
        RowSeparator()
        NavigationLink { SourcesScreen(store: store) } label: {
            ListRow(title: "Sources", icon: "arrow.triangle.2.circlepath", showsChevron: true)
        }
        .buttonStyle(RowPressStyle())
        let pending = PendingSaves.urls.count
        if pending > 0 {
            RowSeparator()
            ListRow(title: "On this phone, not sent yet", icon: "iphone", value: pending.counted("save"))
        }
    }
}

private struct ConnectionGroup: View {
    let store: LibraryStore
    var onDisconnect: () -> Void

    @State private var isConfirmingDisconnect = false

    private var status: (label: String, color: Color) {
        if store.failure != nil { return ("Can't reach Pond", .red) }
        if store.info == nil { return ("Checking…", Theme.muted) }
        return ("Connected", Theme.accent)
    }

    var body: some View {
        SectionHeading("Connection")
        ListRow(title: "Pond", icon: "desktopcomputer", value: store.info?.name)
        RowSeparator()
        ListRow(title: "Address", icon: "network", value: store.api.connection.baseURL.host())
        RowSeparator()
        ListRow(title: "Status", icon: "circle.fill", value: status.label, iconColor: status.color)
            .animation(.snappy(duration: 0.25), value: status.label)
        RowSeparator()
        Button { isConfirmingDisconnect = true } label: {
            ListRow(title: "Disconnect", icon: "rectangle.portrait.and.arrow.right", iconColor: .red, titleColor: .red)
        }
        .buttonStyle(RowPressStyle())
        .confirmationDialog("Disconnect from Pond?", isPresented: $isConfirmingDisconnect, titleVisibility: .visible) {
            Button("Disconnect", role: .destructive, action: onDisconnect)
        } message: {
            Text("Ripple forgets this address and token. Your saves stay on your Mac.")
        }
    }
}
