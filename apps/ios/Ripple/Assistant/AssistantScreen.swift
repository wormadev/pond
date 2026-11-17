import SwiftUI

struct AssistantChat: Decodable, Identifiable, Hashable {
    var id: String
    var title: String?
    var updatedAt: String?

    var displayTitle: String { title?.isEmpty == false ? title! : "New Chat" }
}

/// Pond's Assistant chats, run by the Mac with the provider keys set up there.
struct AssistantScreen: View {
    let store: LibraryStore

    @State private var chats: [AssistantChat]?
    @State private var failure: String?
    @State private var opened: AssistantChat?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ScreenHeader(title: "Assistant") {
                    Button("New Chat", systemImage: "square.and.pencil") { newChat() }
                        .labelStyle(.iconOnly)
                        .font(.textStrong)
                        .foregroundStyle(Theme.foreground)
                        .frame(width: Theme.unit * 9, height: Theme.unit * 9)
                        .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
                }
                if let failure, chats == nil {
                    StateMessage(title: "Couldn't load chats", detail: failure, actionTitle: "Try again") {
                        Task { await load() }
                    }
                } else if let chats {
                    if chats.isEmpty {
                        StateMessage(title: "No chats yet", detail: "Ask about your Library. Pond answers on your Mac.", actionTitle: "New Chat") { newChat() }
                    }
                    ForEach(chats) { chat in
                        NavigationLink(value: chat) {
                            ListRow(title: chat.displayTitle, icon: "bubble.left", value: relative(chat.updatedAt), showsChevron: true)
                        }
                        .buttonStyle(RowPressStyle())
                        if chat.id != chats.last?.id { RowSeparator() }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, Theme.unit * 8)
                }
            }
            .padding(.bottom, Theme.unit * 8)
        }
        .background(Theme.background)
        .navigationTitle("Assistant")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: AssistantChat.self) { ChatScreen(api: store.api, chat: $0) }
        .navigationDestination(item: $opened) { ChatScreen(api: store.api, chat: $0) }
        .refreshable { await load() }
        .task { await load() }
        .alert("Couldn't start a chat", isPresented: Binding(get: { failure != nil && chats != nil }, set: { if !$0 { failure = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(failure ?? "")
        }
    }

    private func relative(_ raw: String?) -> String? {
        guard let raw, let date = try? Date(raw, strategy: .iso8601) else { return nil }
        return date.formatted(.relative(presentation: .named))
    }

    private func load() async {
        do {
            let loaded: [AssistantChat] = try await store.api.operation("agent.chats")
            chats = loaded.sorted { ($0.updatedAt ?? "") > ($1.updatedAt ?? "") }
            failure = nil
        } catch is CancellationError {
        } catch {
            failure = error.pondMessage
        }
    }

    private func newChat() {
        Task {
            do {
                let chat: AssistantChat = try await store.api.operation("agent.newChat", review: true)
                opened = chat
                await load()
            } catch {
                failure = error.pondMessage
            }
        }
    }
}
