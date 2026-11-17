import SwiftUI
import UIKit

@MainActor
enum SnapshotMatrix {
    struct Device {
        let name: String
        let size: CGSize
    }

    static let devices = [
        Device(name: "375", size: CGSize(width: 375, height: 667)),
        Device(name: "402", size: CGSize(width: 402, height: 874)),
        Device(name: "440", size: CGSize(width: 440, height: 956)),
    ]
    static let textSizes: [(name: String, category: UIContentSizeCategory)] = [
        ("default", .large),
        ("xxxl", .extraExtraExtraLarge),
        ("ax3", .accessibilityExtraLarge),
    ]
    static let styles: [(name: String, style: UIUserInterfaceStyle)] = [("light", .light), ("dark", .dark)]

    @discardableResult
    static func render(_ name: String, to directory: URL, @ViewBuilder content: @escaping () -> some View) async throws -> URL {
        let folder = directory.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var rows: [[(label: String, image: UIImage)]] = []
        for style in styles {
            for text in textSizes {
                var row: [(String, UIImage)] = []
                for device in devices {
                    let image = try await cell(content: content, device: device, category: text.category, style: style.style)
                    let label = "\(device.name)-\(text.name)-\(style.name)"
                    try image.pngData()?.write(to: folder.appending(path: "\(label).png"))
                    row.append((label, image))
                }
                rows.append(row)
            }
        }
        let sheet = folder.appending(path: "sheet.png")
        try contactSheet(rows).pngData()?.write(to: sheet)
        return sheet
    }

    /// Sleeps instead of spinning the run loop: screens load in `.task`, which only runs once this job yields the main actor.
    private static func cell(content: () -> some View, device: Device, category: UIContentSizeCategory, style: UIUserInterfaceStyle) async throws -> UIImage {
        let bounds = CGRect(origin: .zero, size: device.size)
        let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
        let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow(frame: bounds)
        window.frame = bounds
        let host = UIHostingController(rootView: content())
        host.traitOverrides.preferredContentSizeCategory = category
        host.overrideUserInterfaceStyle = style
        window.rootViewController = host
        window.isHidden = false
        host.view.frame = bounds
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(500))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        let image = UIGraphicsImageRenderer(bounds: bounds, format: format).image { context in
            if scene == nil || !host.view.drawHierarchy(in: bounds, afterScreenUpdates: true) {
                host.view.layer.render(in: context.cgContext)
            }
        }
        window.isHidden = true
        return image
    }

    private static func contactSheet(_ rows: [[(label: String, image: UIImage)]]) -> UIImage {
        let scale: CGFloat = 0.5
        let gap: CGFloat = 16
        let labelHeight: CGFloat = 18
        let cellWidths = devices.map { $0.size.width * scale }
        let rowHeight = (devices.map(\.size.height).max() ?? 0) * scale + labelHeight
        let size = CGSize(
            width: cellWidths.reduce(0, +) + gap * CGFloat(devices.count + 1),
            height: rowHeight * CGFloat(rows.count) + gap * CGFloat(rows.count + 1)
        )
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: UIColor.black]
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(white: 0.9, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))
            for (r, row) in rows.enumerated() {
                var x = gap
                let y = gap + CGFloat(r) * (rowHeight + gap)
                for (c, entry) in row.enumerated() {
                    entry.label.draw(at: CGPoint(x: x, y: y), withAttributes: attributes)
                    let frame = CGRect(x: x, y: y + labelHeight, width: cellWidths[c], height: devices[c].size.height * scale)
                    entry.image.draw(in: frame)
                    x += cellWidths[c] + gap
                }
            }
        }
    }
}
