import SwiftUI

struct DownloadsScreen: View {
    let store: LibraryStore

    var body: some View {
        ScrollView {
            if let info = store.info {
                DownloadsContent(info: info)
            } else if let failure = store.failure {
                StateMessage(title: "Can't reach Pond", detail: failure)
            } else {
                DownloadsSkeleton()
            }
        }
        .background(Theme.background)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("Downloads").font(.textStrong) }
        }
        .toolbarBackground(Theme.background, for: .navigationBar)
        .animation(.snappy(duration: 0.25), value: store.info?.counts.ingesting)
        .refreshable { await store.refreshSidebar() }
        .task {
            while !Task.isCancelled {
                await store.refreshSidebar()
                try? await Task.sleep(for: .seconds(5))
            }
        }
    }
}

private struct DownloadsContent: View {
    let info: LibraryInfo

    private var done: Int { max(info.counts.active - info.counts.ingesting - info.counts.failed, 0) }
    private var isFinished: Bool { info.counts.ingesting == 0 && info.queue.pending == 0 }

    private var status: String {
        if isFinished { return "Everything is imported" }
        return info.queue.running > 0 ? "Pond is downloading now" : "Pond is waiting before it fetches more"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ImportMeter(done: done, total: info.counts.active, status: status)
            SectionHeading("Saves")
            ListRow(title: "Imported", icon: "checkmark.circle", value: done.counted("save"))
            RowSeparator()
            ListRow(title: "Waiting", icon: "clock", value: info.counts.ingesting.counted("save"))
            RowSeparator()
            ListRow(title: "Failed", icon: "exclamationmark.triangle", value: info.counts.failed.counted("save"),
                    iconColor: info.counts.failed > 0 ? .red : Theme.muted)
            let pending = PendingSaves.urls.count
            if pending > 0 {
                RowSeparator()
                ListRow(title: "On this phone, not sent yet", icon: "iphone", value: pending.counted("save"))
            }
            if !isFinished {
                SectionHeading("Tasks")
                ListRow(title: "Queued", icon: "list.bullet", value: info.queue.pending.counted("task"))
                RowSeparator()
                ListRow(title: "Running", icon: "arrow.triangle.2.circlepath", value: info.queue.running.counted("task"))
            }
        }
        .padding(.bottom, Theme.unit * 8)
    }
}

private struct ImportMeter: View {
    let done: Int
    let total: Int
    let status: String

    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 2) {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.unit))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.unit * 3))
            layout {
                Text("Imported").foregroundStyle(Theme.muted)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                ViewThatFits(in: .horizontal) {
                    Text("\(done.formatted()) of \(total.formatted())").fixedSize()
                    Text("\(done.formatted()) / \(total.formatted())")
                        .lineLimit(1)
                        .minimumScaleFactor(0.5)
                }
                .font(.display)
                .monospacedDigit()
                .contentTransition(.numericText())
            }
            ProgressBar(fraction: Double(done) / Double(max(total, 1)))
            Text(status).font(.small).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.top, Theme.unit * 4)
    }
}

private struct ProgressBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { proxy in
            Theme.accent
                .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.surface)
                .clipShape(.rect(cornerRadius: Theme.unit / 2))
        }
        .frame(height: Theme.unit)
        .accessibilityElement()
        .accessibilityValue(Text(fraction, format: .percent.precision(.fractionLength(0))))
    }
}

private struct DownloadsSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.unit * 2) {
                HStack {
                    Skeleton().frame(width: Theme.unit * 16, height: Theme.unit * 4)
                    Spacer(minLength: 0)
                    Skeleton().frame(width: Theme.unit * 44, height: Theme.unit * 8)
                }
                Skeleton(radius: Theme.unit / 2).frame(height: Theme.unit)
                Skeleton().frame(width: Theme.unit * 48, height: Theme.unit * 3)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.unit * 4)
            SectionHeading("Saves")
            ForEach(0..<3, id: \.self) { index in
                if index > 0 { RowSeparator() }
                Skeleton()
                    .frame(height: Theme.unit * 5)
                    .padding(.vertical, Theme.unit * 3)
                    .padding(.horizontal, Theme.gutter)
            }
        }
    }
}

extension Int {
    func counted(_ noun: String) -> String {
        "\(formatted()) \(self == 1 ? noun : noun + "s")"
    }
}
