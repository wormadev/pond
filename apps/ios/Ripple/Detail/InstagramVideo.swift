import AVKit
import SwiftUI
import WebKit

/// Plays an Instagram video Pond hasn't downloaded, straight from Instagram.
struct InstagramVideo: View {
    let save: Save
    let isCurrent: Bool

    private enum Phase {
        case loading
        case playing(AVPlayer)
        case needsSignIn
        /// Signed in but the file's address still isn't offered: show Instagram's own page.
        case page(URL)
    }

    @State private var phase = Phase.loading
    @State private var signsIn = false

    /// `/reel/<code>/` and `/p/<code>/` both have an `/embed/` page.
    static func embedURL(for save: Save) -> URL? {
        guard save.source == "instagram", let parts = URL(string: save.url)?.pathComponents.filter({ $0 != "/" }),
              parts.count >= 2, ["reel", "reels", "p", "tv"].contains(parts[0])
        else { return nil }
        return URL(string: "https://www.instagram.com/\(parts[0] == "reels" ? "reel" : parts[0])/\(parts[1])/embed/")
    }

    var body: some View {
        ZStack {
            switch phase {
            case .loading:
                ProgressView().tint(Theme.muted)
            case .playing(let player):
                VideoPlayer(player: player).onDisappear { player.pause() }
            case .needsSignIn:
                VStack(spacing: Theme.unit * 3) {
                    Text("Instagram wants you signed in to play this.")
                        .multilineTextAlignment(.center)
                    Button("Sign in to Instagram") { signsIn = true }
                        .buttonStyle(ControlButtonStyle())
                }
                .padding(Theme.gutter)
            case .page(let url):
                InstagramPage(url: url)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onChange(of: isCurrent) { _, current in
            guard case .playing(let player) = phase else { return }
            if current { player.play() } else { player.pause() }
        }
        .task { await load() }
        .sheet(isPresented: $signsIn, onDismiss: { Task { await load() } }) {
            InstagramSignIn()
        }
    }

    private func load() async {
        phase = .loading
        guard let embed = Self.embedURL(for: save) else { return }
        let cookies = await WKWebsiteDataStore.default().httpCookieStore.allCookies().filter { $0.domain.contains("instagram.com") }
        let isSignedIn = cookies.contains { $0.name == "sessionid" }
        // Anonymous first: Instagram hides the file from a half-formed browser session, so cookies only help once signed in.
        for session in isSignedIn ? [[], cookies] : [[]] {
            if let video = await Self.videoURL(in: embed, cookies: session) {
                let player = AVPlayer(url: video)
                phase = .playing(player)
                if isCurrent { player.play() }
                return
            }
        }
        phase = isSignedIn ? .page(embed.deletingLastPathComponent()) : .needsSignIn
    }

    /// No cookie jar: a stored anonymous Instagram cookie makes later requests come back without the file.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        return URLSession(configuration: config)
    }()

    /// The embed page carries the file's address as escaped JSON.
    private static func videoURL(in page: URL, cookies: [HTTPCookie]) async -> URL? {
        var request = URLRequest(url: page)
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        for (field, value) in HTTPCookie.requestHeaderFields(with: cookies) where !cookies.isEmpty {
            request.setValue(value, forHTTPHeaderField: field)
        }
        guard let (data, _) = try? await Self.session.data(for: request),
              let html = String(data: data, encoding: .utf8),
              let match = html.firstMatch(of: /video_url\\*":\\*"(https[^"]+?)\\*"/)
        else { return nil }
        let address = String(match.1)
            .replacing(/\\+u0026/, with: "&")
            .replacing("\\", with: "")
        return URL(string: address)
    }
}

/// Instagram's own sign-in page. The session stays in the app's web storage; Ripple never sees the password.
private struct InstagramSignIn: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            InstagramPage(url: URL(string: "https://www.instagram.com/accounts/login/")!)
                .ignoresSafeArea(edges: .bottom)
                .navigationTitle("Instagram")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }.tint(Theme.accent)
                    }
                }
        }
    }
}

private struct InstagramPage: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let view = WKWebView(frame: .zero, configuration: config)
        view.isOpaque = false
        view.backgroundColor = UIColor(Theme.background)
        view.scrollView.backgroundColor = UIColor(Theme.background)
        view.load(URLRequest(url: url))
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {}
}
