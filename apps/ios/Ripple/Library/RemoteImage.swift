import SwiftUI

actor ImageLoader {
    static let shared = ImageLoader()
    private let cache = NSCache<NSURL, UIImage>()

    func image(for request: URLRequest, session: URLSession) async throws -> UIImage {
        guard let url = request.url else { throw URLError(.badURL) }
        if let hit = cache.object(forKey: url as NSURL) { return hit }
        let (data, _) = try await session.data(for: request)
        guard let image = UIImage(data: data), let ready = await image.byPreparingForDisplay() else {
            throw URLError(.cannotDecodeContentData)
        }
        cache.setObject(ready, forKey: url as NSURL)
        return ready
    }
}

/// Loads an authenticated image and fades it in.
struct RemoteImage: View {
    let request: URLRequest
    let session: URLSession
    var contentMode = ContentMode.fill
    var onLoad: ((UIImage) -> Void)?

    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        ZStack {
            if image == nil { Theme.surface }
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else if failed {
                Image(systemName: "photo")
                    .font(.heading)
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
        }
        .task(id: request.url) {
            do {
                let loaded = try await ImageLoader.shared.image(for: request, session: session)
                onLoad?(loaded)
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            } catch {
                guard !Task.isCancelled else { return }
                withAnimation(.easeOut(duration: 0.2)) { failed = true }
            }
        }
    }
}
