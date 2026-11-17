import NaturalLanguage
import SwiftUI

/// Where content under a `ListRow` starts: in line with the row's title.
private let rowContentInset = Theme.gutter + Theme.iconColumn + Theme.unit * 3

struct SaveHeader: View {
    let save: Save

    var body: some View {
        let author = save.author.flatMap { $0.isEmpty ? nil : $0 }
        let title = author ?? save.siteName ?? save.source.capitalized
        let date = save.savedDate.formatted(date: .abbreviated, time: .shortened)
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(title)
                .font(.heading)
                .lineLimit(2)
                .truncationMode(.middle)
                .accessibilityAddTraits(.isHeader)
            Text(author == nil ? date : "\(save.source.capitalized) · \(date)")
                .font(.small)
                .foregroundStyle(Theme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .naturalDirection(of: title)
        .padding(.horizontal, Theme.gutter)
    }
}

/// Rating, tags, folders and note as one group of rows.
struct SaveProperties: View {
    let save: Save
    let folderNames: [String]
    let rate: (Int) -> Void
    let open: (SaveEditor) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Theme.border.frame(height: 0.5).padding(.horizontal, Theme.gutter)
            RatingRow(rating: save.rating ?? 0, rate: rate)
            RowSeparator()
            ChipsField(title: "Tags", icon: "tag", values: save.tags) { open(.tags) }
            RowSeparator()
            ChipsField(title: "Folders", icon: "folder", values: folderNames) { open(.folders) }
            RowSeparator()
            NoteField(note: save.note ?? "") { open(.note) }
        }
    }
}

/// At accessibility text sizes the stars drop under the label instead of squeezing it.
private struct RatingRow: View {
    let rating: Int
    let rate: (Int) -> Void

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stacked = typeSize.isAccessibilitySize
        let layout = stacked
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Theme.unit * 3))
        HStack(alignment: .top, spacing: Theme.unit * 3) {
            Image(systemName: "star")
                .foregroundStyle(Theme.muted)
                .frame(width: Theme.iconColumn, height: Theme.rowHeight)
            layout {
                Text("Rating").frame(minHeight: Theme.rowHeight)
                if !stacked { Spacer(minLength: 0) }
                // The 44pt hit areas are wider than the glyphs; pull them out so the glyphs line up with the text edge.
                Stars(rating: rating, rate: rate)
                    .padding(stacked ? .leading : .trailing, -Theme.unit * 3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Theme.gutter)
    }
}

private struct Stars: View {
    let rating: Int
    let rate: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...5, id: \.self) { star in
                let filled = star <= rating
                Button {
                    rate(rating == star ? 0 : star)
                } label: {
                    Image(systemName: filled ? "star.fill" : "star")
                        .font(.heading)
                        .foregroundStyle(filled ? Theme.accent : Theme.muted)
                        .symbolEffect(.bounce, value: rating)
                        .frame(width: Theme.rowHeight, height: Theme.rowHeight)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(star == 1 ? "1 star" : "\(star) stars")
                .accessibilityAddTraits(filled ? .isSelected : [])
            }
        }
        .sensoryFeedback(.selection, trigger: rating)
    }
}

private struct ChipsField: View {
    let title: String
    let icon: String
    let values: [String]
    let open: () -> Void

    var body: some View {
        Button(action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ListRow(title: title, icon: icon, value: values.isEmpty ? "Add" : nil, showsChevron: true)
                if !values.isEmpty {
                    Chips(values: values)
                        .padding(.leading, rowContentInset)
                        .padding(.trailing, Theme.gutter)
                        .padding(.bottom, Theme.unit * 3)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(RowPressStyle())
    }
}

/// The note sits outside the row's button so its More/Less control stays tappable.
private struct NoteField: View {
    let note: String
    let open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: open) {
                ListRow(title: "Note", icon: "note.text", value: note.isEmpty ? "Add" : nil, showsChevron: true)
            }
            .buttonStyle(RowPressStyle())
            if !note.isEmpty {
                ClampedText(text: note)
                    .padding(.leading, rowContentInset)
                    .padding(.trailing, Theme.gutter)
                    .padding(.bottom, Theme.unit * 3)
            }
        }
    }
}

private struct Chips: View {
    let values: [String]

    var body: some View {
        FlowLayout(spacing: Theme.unit * 2) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.small)
                    .foregroundStyle(Theme.foreground)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, Theme.unit * 2)
                    .padding(.vertical, Theme.unit)
                    .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusCard))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusCard).strokeBorder(Theme.border, lineWidth: 0.5))
            }
        }
    }
}

/// Clamped to four lines, offering "More" only when the text is actually cut off.
struct ClampedText: View {
    let text: String

    @State private var expanded = false
    @State private var fullHeight: CGFloat = 0
    @State private var clampedHeight: CGFloat = 0
    private let lines = 4

    private var isTruncated: Bool { fullHeight > clampedHeight + 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit) {
            Text(text)
                .lineLimit(expanded ? nil : lines)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self, of: \.size.height) { if !expanded { clampedHeight = $0 } }
                .background(alignment: .top) {
                    Text(text)
                        .fixedSize(horizontal: false, vertical: true)
                        .hidden()
                        .onGeometryChange(for: CGFloat.self, of: \.size.height) { fullHeight = $0 }
                }
            if isTruncated || expanded {
                Button(expanded ? "Less" : "More") {
                    withAnimation(.snappy(duration: 0.25)) { expanded.toggle() }
                }
                .font(.small)
                .foregroundStyle(Theme.muted)
                .buttonStyle(.plain)
            }
        }
        .naturalDirection(of: text)
    }
}

extension View {
    /// Aligns right-to-left text (Arabic, Hebrew) by its own direction instead of the app's.
    func naturalDirection(of text: String) -> some View {
        environment(\.layoutDirection, text.isRightToLeft ? .rightToLeft : .leftToRight)
    }
}

private extension String {
    var isRightToLeft: Bool {
        guard let language = NLLanguageRecognizer.dominantLanguage(for: self) else { return false }
        return Locale.Language(identifier: language.rawValue).characterDirection == .rightToLeft
    }
}

/// Wraps its children into rows. A child wider than the row is offered the row's width, so text truncates inside it.
private struct FlowLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = place(subviews, width: proposal.width)
        return CGSize(width: proposal.width ?? rows.width, height: rows.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let rows = place(subviews, width: bounds.width)
        for (subview, frame) in zip(subviews, rows.frames) {
            subview.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY), proposal: ProposedViewSize(frame.size))
        }
    }

    private func place(_ subviews: Subviews, width: CGFloat?) -> (frames: [CGRect], width: CGFloat, height: CGFloat) {
        let limit = width ?? .infinity
        var frames: [CGRect] = []
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
            if x > 0, x + size.width > limit {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            frames.append(CGRect(origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            widest = max(widest, x - spacing)
        }
        return (frames, widest, y + rowHeight)
    }
}
