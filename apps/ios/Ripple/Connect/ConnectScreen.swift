import SwiftUI

struct ConnectScreen: View {
    var onConnect: (Connection) -> Void

    enum Field { case address, token }

    struct Failure: Equatable {
        var field: Field
        var message: String
    }

    @State private var address = ""
    @State private var token = ""
    @State private var isChecking = false
    @State private var failure: Failure?
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.unit * 6) {
                VStack(alignment: .leading, spacing: Theme.unit * 2) {
                    Text("Connect to Pond").font(.display).accessibilityAddTraits(.isHeader)
                    Text("Enter your Mac's address and a token from Pond's Settings, under Local API.")
                        .foregroundStyle(Theme.muted)
                }
                LabeledField(label: "Address", prompt: "https://your-mac.ts.net:41610", text: $address,
                             field: .address, focus: $focus, error: failure?.field == .address ? failure?.message : nil)
                    .keyboardType(.URL)
                    .textContentType(.URL)
                    .submitLabel(.next)
                    .onSubmit { focus = .token }
                LabeledField(label: "Token", prompt: "pond_…", text: $token,
                             field: .token, focus: $focus, error: failure?.field == .token ? failure?.message : nil)
                    .submitLabel(.go)
                    .onSubmit(connect)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, Theme.unit * 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            ConnectButton(isChecking: isChecking, action: connect)
                .padding(.horizontal, Theme.gutter)
                .padding(.vertical, Theme.unit * 3)
                .background(Theme.background)
        }
        .background(Theme.background)
        .animation(.snappy(duration: 0.2), value: failure)
        .onChange(of: address) { if failure?.field == .address { failure = nil } }
        .onChange(of: token) { if failure?.field == .token { failure = nil } }
    }

    private func connect() {
        guard !isChecking else { return }
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme == "https", url.host() != nil else {
            fail(.address, "Enter an https address, like https://your-mac.ts.net:41610.")
            return
        }
        let key = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else {
            fail(.token, "Paste the token from Pond's Settings, under Local API.")
            return
        }
        let connection = Connection(baseURL: url, token: key)
        isChecking = true
        failure = nil
        Task {
            defer { isChecking = false }
            do {
                _ = try await PondAPI(connection: connection).libraryInfo()
                try ConnectionStore.save(connection)
                onConnect(connection)
            } catch {
                fail(error is PondError ? .token : .address, error.pondMessage)
            }
        }
    }

    private func fail(_ field: Field, _ message: String) {
        failure = Failure(field: field, message: message)
        focus = field
    }
}

private struct LabeledField: View {
    let label: String
    let prompt: String
    @Binding var text: String
    let field: ConnectScreen.Field
    var focus: FocusState<ConnectScreen.Field?>.Binding
    let error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 2) {
            Text(label).font(.textStrong)
            TextField(label, text: $text, prompt: Text(prompt).foregroundStyle(Theme.muted))
                .font(.heading)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focus, equals: field)
                .padding(.horizontal, Theme.unit * 3)
                .padding(.vertical, Theme.unit * 2)
                .frame(minHeight: Theme.rowHeight)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.border, lineWidth: 0.5))
            if let error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.small)
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
        }
    }
}

private struct ConnectButton: View {
    let isChecking: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.unit * 2) {
                if isChecking { ProgressView().tint(.white) }
                Text(isChecking ? "Checking…" : "Connect")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(ControlButtonStyle(isPrimary: true))
        .disabled(isChecking)
    }
}
