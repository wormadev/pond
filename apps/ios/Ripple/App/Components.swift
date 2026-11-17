import SwiftUI

/// The title block every root and pushed screen opens with.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .bottom, spacing: Theme.unit * 3) {
            VStack(alignment: .leading, spacing: Theme.unit) {
                Text(title)
                    .font(.display)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
                    .accessibilityAddTraits(.isHeader)
                if let subtitle {
                    Text(subtitle).font(.small).foregroundStyle(Theme.muted).contentTransition(.numericText())
                }
            }
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.unit * 4)
        .padding(.bottom, Theme.unit * 3)
    }
}

extension ScreenHeader where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

struct SectionHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.heading)
            .accessibilityAddTraits(.isHeader)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.unit * 8)
            .padding(.bottom, Theme.unit * 3)
    }
}

/// Icon, title and an optional value. At accessibility text sizes the value drops under the title instead of squeezing it.
struct ListRow: View {
    let title: String
    let icon: String
    var value: String?
    var iconColor = Theme.muted
    var titleColor = Theme.foreground
    var showsChevron = false

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.unit * 3) {
            Image(systemName: icon).frame(width: Theme.iconColumn).foregroundStyle(iconColor)
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.unit))
                : AnyLayout(HStackLayout(spacing: Theme.unit * 3))
            layout {
                Text(title).foregroundStyle(titleColor)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let value {
                    Text(value)
                        .font(.small)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(typeSize.isAccessibilitySize ? 2 : 1)
                        .truncationMode(.middle)
                        .contentTransition(.numericText())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if showsChevron {
                Image(systemName: "chevron.right").font(.small).foregroundStyle(Theme.muted)
            }
        }
        .padding(.vertical, Theme.unit * 3)
        .frame(minHeight: Theme.rowHeight)
        .padding(.horizontal, Theme.gutter)
        .contentShape(.rect)
    }
}

/// Hairline under a `ListRow`, starting at its title.
struct RowSeparator: View {
    var body: some View {
        Theme.border
            .frame(height: 0.5)
            .padding(.leading, Theme.gutter + Theme.iconColumn + Theme.unit * 3)
            .padding(.trailing, Theme.gutter)
    }
}

struct RowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? Theme.surface : .clear)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// Empty, failed and first-use states: one line that names the state, one that says what to do, at most one action.
struct StateMessage: View {
    let title: String
    let detail: String
    var actionTitle: String?
    var action: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 2) {
            Text(title).font(.heading)
            Text(detail).foregroundStyle(Theme.muted)
            if let actionTitle {
                Button(actionTitle, action: action)
                    .buttonStyle(ControlButtonStyle())
                    .padding(.top, Theme.unit * 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.unit * 6)
    }
}

/// The secondary control: surface fill, control radius, grows with its label.
struct ControlButtonStyle: ButtonStyle {
    var isPrimary = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.textStrong)
            .foregroundStyle(isPrimary ? Color.white : Theme.foreground)
            .padding(.horizontal, Theme.unit * 4)
            .padding(.vertical, Theme.unit * 3)
            .frame(minHeight: Theme.rowHeight)
            .background(isPrimary ? AnyShapeStyle(Theme.accent) : AnyShapeStyle(Theme.surface), in: .rect(cornerRadius: Theme.radiusControl))
            .opacity(configuration.isPressed ? 0.7 : 1)
            .animation(.snappy(duration: 0.15), value: configuration.isPressed)
    }
}

/// A placeholder with the geometry of the content it stands in for.
struct Skeleton: View {
    var radius = Theme.radiusCard

    @State private var isDim = false

    var body: some View {
        Theme.surface
            .clipShape(.rect(cornerRadius: radius))
            .opacity(isDim ? 0.5 : 1)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: isDim)
            .onAppear { isDim = true }
            .accessibilityHidden(true)
    }
}

extension Error {
    /// What went wrong and what to do about it, in words the person can act on.
    var pondMessage: String {
        if let error = self as? PondError {
            switch error.code {
            case "unauthorized": return "Pond turned down this token. Disconnect in Settings and connect again with a new one."
            case "forbidden": return "This token can't do that. In Pond on your Mac, open Settings, Local API, and give it the access it needs."
            default: return error.message
            }
        }
        if self is URLError {
            return "Check that your Mac is on, Pond is open, and this phone can reach it."
        }
        return localizedDescription
    }
}
