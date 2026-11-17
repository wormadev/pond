import AVKit
import SwiftUI

struct MediaPager: View {
    let save: Save
    let files: [SaveFile]
    let store: LibraryStore
    var isCurrent = true
    let width: CGFloat
    let maxHeight: CGFloat

    @State private var zoomed: SaveFile?
    @State private var playsEmbed = false

    private var isMissingVideo: Bool {
        save.isVideo && !files.isEmpty && !media.contains(where: \.isVideo)
    }

    /// The post's own media. Pond also stores a poster, a card thumbnail and the author's avatar.
    private var media: [SaveFile] {
        let originals = files.filter { $0.name.hasPrefix("media-") && !$0.name.contains("_thumbnail") }
        return originals.isEmpty ? files.filter { $0.name.hasPrefix("poster-") } : originals
    }

    private var aspect: CGFloat {
        store.aspects[save.id] ?? (save.isVideo ? 9 / 16 : 1)
    }

    /// The box takes the media's shape so it hugs it; a tall reel narrows instead of filling the screen.
    private var box: CGSize {
        let height = min(width / aspect, maxHeight)
        return CGSize(width: height * aspect, height: height)
    }

    var body: some View {
        content
            .frame(width: box.width, height: box.height)
            .clipped()
            .overlay {
                if isMissingVideo, !playsEmbed {
                    MissingVideo(canPlay: InstagramVideo.embedURL(for: save) != nil) {
                        withAnimation(.snappy(duration: 0.2)) { playsEmbed = true }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .onChange(of: isCurrent) { _, current in
                if !current { playsEmbed = false }
            }
            .fullScreenCover(item: $zoomed) { file in
                ZoomedImage(request: store.api.fileRequest(id: save.id, index: file.index), session: store.api.session)
            }
    }

    @ViewBuilder
    private var content: some View {
        if playsEmbed {
            InstagramVideo(save: save, isCurrent: isCurrent)
        } else if media.isEmpty {
            RemoteImage(
                request: store.api.thumbRequest(id: save.id, size: "large"),
                session: store.api.session,
                contentMode: .fit,
                onLoad: { image in
                    guard store.aspects[save.id] == nil, image.size.height > 0 else { return }
                    store.aspects[save.id] = image.size.width / image.size.height
                }
            )
        } else if media.count == 1 {
            page(media[0])
        } else {
            TabView {
                ForEach(media) { file in
                    page(file)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
        }
    }

    @ViewBuilder
    private func page(_ file: SaveFile) -> some View {
        if file.isVideo {
            VideoFile(api: store.api, saveID: save.id, file: file, isCurrent: isCurrent)
        } else {
            RemoteImage(
                request: store.api.fileRequest(id: save.id, index: file.index),
                session: store.api.session,
                contentMode: .fit,
                onLoad: { learnAspect(from: $0, file: file) }
            )
            .onTapGesture { zoomed = file }
        }
    }

    /// Thumbnails can be cropped, so the first full image sets the box's shape.
    private func learnAspect(from image: UIImage, file: SaveFile) {
        guard file.id == media.first?.id, image.size.height > 0 else { return }
        let measured = image.size.width / image.size.height
        guard abs(measured - aspect) > 0.01 else { return }
        withAnimation(.snappy(duration: 0.25)) { store.aspects[save.id] = measured }
    }
}

/// A video Pond hasn't downloaded: play it from Instagram, or say why it can't play.
private struct MissingVideo: View {
    let canPlay: Bool
    let play: () -> Void

    var body: some View {
        if canPlay {
            Button("Play from Instagram", systemImage: "play.fill", action: play)
                .buttonStyle(MediaControlStyle())
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else {
            Label("Not downloaded on your Mac yet", systemImage: "arrow.down.circle")
                .font(.small)
                .padding(.horizontal, Theme.unit * 3)
                .padding(.vertical, Theme.unit * 2)
                .background(Theme.background, in: .rect(cornerRadius: Theme.radiusCard))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border, lineWidth: 0.5))
                .padding(Theme.unit * 3)
        }
    }
}

/// Pond serves files without byte ranges, which AVPlayer needs, so the video is downloaded first.
private struct VideoFile: View {
    let api: PondAPI
    let saveID: String
    let file: SaveFile
    let isCurrent: Bool

    @State private var player: AVPlayer?
    @State private var failed = false

    var body: some View {
        ZStack {
            if let player {
                VideoPlayer(player: player).onDisappear { player.pause() }
            } else if failed {
                Label("Couldn't load this video", systemImage: "exclamationmark.triangle").foregroundStyle(Theme.muted)
            } else {
                ProgressView()
            }
        }
        .onChange(of: isCurrent) { _, current in
            if current { player?.play() } else { player?.pause() }
        }
        .task {
            do {
                let local = URL.cachesDirectory.appending(path: "\(saveID)-\(file.index)-\(file.name)")
                if !FileManager.default.fileExists(atPath: local.path()) {
                    let (temp, _) = try await api.session.download(for: api.fileRequest(id: saveID, index: file.index))
                    try FileManager.default.moveItem(at: temp, to: local)
                }
                let player = AVPlayer(url: local)
                self.player = player
                if isCurrent { player.play() }
            } catch {
                failed = true
            }
        }
    }
}

private struct ZoomedImage: View {
    let request: URLRequest
    let session: URLSession

    @State private var scale: CGFloat = 1
    @State private var settled: CGFloat = 1
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        RemoteImage(request: request, session: session, contentMode: .fit)
            .scaleEffect(scale)
            .gesture(
                MagnifyGesture()
                    .onChanged { scale = max(1, settled * $0.magnification) }
                    .onEnded { _ in settled = scale }
            )
            .onTapGesture(count: 2) {
                withAnimation(.snappy) {
                    scale = scale > 1 ? 1 : 2.5
                    settled = scale
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
            .overlay(alignment: .topTrailing) {
                Button("Close", systemImage: "xmark") { dismiss() }
                    .buttonStyle(MediaControlStyle())
                    .padding(.horizontal, Theme.unit * 4)
                    .padding(.top, Theme.unit * 2)
            }
    }
}

/// Square icon control that stays legible over any media. Pinned to one text size so it never outgrows the media.
private struct MediaControlStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.heading)
            .dynamicTypeSize(.large)
            .foregroundStyle(Theme.foreground)
            .frame(width: Theme.rowHeight, height: Theme.rowHeight)
            .background(Theme.background, in: .rect(cornerRadius: Theme.radiusControl))
            .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.border, lineWidth: 0.5))
            .contentShape(.rect(cornerRadius: Theme.radiusControl))
            .opacity(configuration.isPressed ? 0.6 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
