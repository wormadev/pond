import SwiftUI
import UIKit
import UniformTypeIdentifiers

final class ShareViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(context: extensionContext))
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        host.view.backgroundColor = .clear
        view.addSubview(host.view)
        host.didMove(toParent: self)
    }
}

private struct ShareView: View {
    let context: NSExtensionContext?

    private enum Outcome {
        case saved, alreadySaved, queued, failed(String)
    }

    @State private var outcome: Outcome?

    // Theme.swift and Inter are not in this target; these mirror Theme's background, foreground and accent.
    private let background = Color(red: 0.039, green: 0.039, blue: 0.039)
    private let foreground = Color(red: 0.933, green: 0.933, blue: 0.933)
    private let accent = Color(red: 0, green: 0.561, blue: 1)
    private var muted: Color { foreground.opacity(0.55) }

    var body: some View {
        VStack(spacing: 12) {
            switch outcome {
            case nil:
                ProgressView().tint(muted)
                Text("Saving to Pond")
            case .saved:
                icon("checkmark.circle.fill", accent)
                Text("Saved to Pond")
            case .alreadySaved:
                icon("checkmark.circle", accent)
                Text("Already in your library")
            case .queued:
                icon("clock", muted)
                Text("Your Mac isn't reachable")
                Text("Ripple will send this when it is.").font(.system(size: 14)).foregroundStyle(muted)
            case .failed(let message):
                icon("exclamationmark.circle", .red)
                Text(message).multilineTextAlignment(.center)
            }
        }
        .font(.system(size: 16, weight: .medium))
        .padding(24)
        .foregroundStyle(foreground)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .preferredColorScheme(.dark)
        .animation(.snappy(duration: 0.25), value: outcome != nil)
        .task {
            let result = await save()
            outcome = result
            try? await Task.sleep(for: .seconds(1.4))
            context?.completeRequest(returningItems: nil)
        }
    }

    private func icon(_ name: String, _ color: Color) -> some View {
        Image(systemName: name).font(.system(size: 26)).foregroundStyle(color).transition(.scale.combined(with: .opacity))
    }

    private func save() async -> Outcome {
        guard let url = await sharedURL() else { return .failed("There's no link to save here.") }
        guard let connection = ConnectionStore.load() else { return .failed("Open Ripple and connect to Pond first.") }
        var api = PondAPI(connection: connection)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 6
        api.session = URLSession(configuration: config)
        do {
            return try await api.enqueue(url: url).created ? .saved : .alreadySaved
        } catch let error as PondError {
            return .failed(error.message)
        } catch {
            PendingSaves.add(url)
            return .queued
        }
    }

    private func sharedURL() async -> String? {
        let providers = (context?.inputItems as? [NSExtensionItem] ?? []).flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL,
               url.scheme?.hasPrefix("http") == true {
                return url.absoluteString
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            guard let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
                  let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue),
                  let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let url = match.url, url.scheme?.hasPrefix("http") == true
            else { continue }
            return url.absoluteString
        }
        return nil
    }
}
