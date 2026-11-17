import SwiftUI

/// A Save's thumbnail, cropped to fill whatever frame it is given.
struct SaveTile: View {
    let save: Save
    let store: LibraryStore
    var size = "medium"

    var body: some View {
        Group {
            if save.thumbnail {
                RemoteImage(
                    request: store.api.thumbRequest(id: save.id, size: size),
                    session: store.api.session
                ) { image in
                    guard store.aspects[save.id] == nil, image.size.height > 0 else { return }
                    store.aspects[save.id] = image.size.width / image.size.height
                }
            } else {
                let downloading = save.status == "ingesting"
                Theme.surface.overlay {
                    Image(systemName: downloading ? "arrow.down.circle" : "link")
                        .font(.heading)
                        .foregroundStyle(Theme.muted)
                        .symbolEffect(.pulse, isActive: downloading)
                }
            }
        }
        .clipped()
        .contentShape(.rect)
    }
}

/// Shrinks and dims a tile or control while a finger is on it.
struct TilePressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.8 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}
