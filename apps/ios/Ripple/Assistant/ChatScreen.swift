import SwiftUI

private struct ChatMessage: Decodable, Identifiable {
    var id: String
    var role: String
    var content: String
}

private struct ProviderModels: Decodable {
    struct Model: Decodable { var id: String }
    var provider: String
    var models: [Model]
}

private struct AvailableModels: Decodable { var providers: [ProviderModels] }

/// One Assistant chat. Pond writes the reply when it finishes, so the screen polls while a reply is running.
struct ChatScreen: View {
    let api: PondAPI
    let chat: AssistantChat

    @State private var messages: [ChatMessage] = []
    @State private var draft = ""
    @State private var isReplying = false
    @State private var replyFinished = false
    @State private var failure: String?
    @State private var providers: [ProviderModels] = []
    @AppStorage("assistant.provider") private var provider = ""
    @FocusState private var composing: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: Theme.unit * 4) {
                    ForEach(messages.filter { $0.role == "user" || $0.role == "assistant" }) { message in
                        Bubble(message: message).id(message.id)
                    }
                    if isReplying {
                        HStack(spacing: Theme.unit * 2) {
                            ProgressView()
                            Text("Thinking on your Mac…").font(.small).foregroundStyle(Theme.muted)
                        }
                        .id("replying")
                        .transition(.opacity)
                    }
                    if let failure {
                        Text(failure).font(.small).foregroundStyle(.red)
                    }
                }
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, Theme.unit * 4)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) {
                withAnimation { proxy.scrollTo(messages.last?.id, anchor: .bottom) }
            }
        }
        .safeAreaInset(edge: .bottom) { composer }
        .background(Theme.background)
        .navigationTitle(chat.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            if !providers.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Provider", selection: $provider) {
                            ForEach(providers, id: \.provider) { Text($0.provider.capitalized).tag($0.provider) }
                        }
                    } label: {
                        Label("Provider", systemImage: "cpu")
                    }
                    .tint(Theme.foreground)
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: isReplying)
        .task { await load() }
    }

    private var composer: some View {
        HStack(alignment: .bottom, spacing: Theme.unit * 2) {
            TextField("Ask about your Library", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($composing)
                .padding(.horizontal, Theme.unit * 3)
                .padding(.vertical, Theme.unit * 2)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
            Button("Send", systemImage: "arrow.up") { send() }
                .labelStyle(.iconOnly)
                .font(.textStrong)
                .foregroundStyle(canSend ? Theme.background : Theme.muted)
                .frame(width: Theme.unit * 9, height: Theme.unit * 9)
                .background(canSend ? Theme.accent : Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
                .disabled(!canSend)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.unit * 2)
        .background(Theme.background)
    }

    private var canSend: Bool {
        !isReplying && !provider.isEmpty && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func load() async {
        async let messages: [ChatMessage]? = try? api.operation("agent.messages", ["chatId": .string(chat.id)])
        async let models: AvailableModels? = try? api.operation("agent.listAvailableModels")
        self.messages = await messages ?? self.messages
        providers = (await models)?.providers.filter { !$0.models.isEmpty } ?? []
        if !providers.contains(where: { $0.provider == provider }) {
            provider = providers.first?.provider ?? ""
        }
        if providers.isEmpty { failure = "Set up an AI provider in Pond on your Mac, under Settings, Assistant." }
    }

    private func send() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let baseline = messages.count
        draft = ""
        failure = nil
        isReplying = true
        replyFinished = false
        messages.append(ChatMessage(id: UUID().uuidString, role: "user", content: content))
        let arguments: [String: JSONValue] = [
            "chatId": .string(chat.id),
            "requestId": .string(UUID().uuidString),
            "content": .string(content),
            "provider": .string(provider),
        ]
        Task {
            do {
                let result: SendResult = try await api.operation("agent.send", arguments, review: true, timeout: 600)
                if let error = result.error { failure = error }
                replyFinished = true
            } catch is URLError {
                // The relay may drop a long request; the reply still lands in the chat, so keep polling.
            } catch {
                failure = error.pondMessage
                replyFinished = true
            }
        }
        Task {
            // Pond writes the reply when it finishes, so poll for it instead of waiting on the send request.
            for _ in 0..<400 {
                try? await Task.sleep(for: .milliseconds(1500))
                let fresh: [ChatMessage]? = try? await api.operation("agent.messages", ["chatId": .string(chat.id)])
                if let fresh { messages = fresh }
                if let fresh, fresh.count >= baseline + 2, fresh.last?.role == "assistant" { break }
                if replyFinished { break }
            }
            isReplying = false
        }
    }
}

private struct SendResult: Decodable {
    var error: String?
}

private struct Bubble: View {
    let message: ChatMessage

    var body: some View {
        let isUser = message.role == "user"
        HStack {
            if isUser { Spacer(minLength: Theme.unit * 12) }
            Text(markdown)
                .textSelection(.enabled)
                .padding(.horizontal, isUser ? Theme.unit * 3 : 0)
                .padding(.vertical, isUser ? Theme.unit * 2 : 0)
                .background(isUser ? Theme.surface : .clear, in: .rect(cornerRadius: Theme.radiusControl))
            if !isUser { Spacer(minLength: 0) }
        }
    }

    private var markdown: AttributedString {
        (try? AttributedString(markdown: message.content, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(message.content)
    }
}
