import SwiftUI

/// Sign in to Pond Connect, then pick the Mac to open.
struct AccountScreen: View {
    var onConnect: (Connection) -> Void

    private enum Field { case email, password }

    @State private var email = ""
    @State private var password = ""
    @State private var isCreating = false
    @State private var isWorking = false
    @State private var failure: String?
    @State private var session: String?
    @State private var machines: [PondAccount.Machine] = []
    @FocusState private var focus: Field?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.unit * 6) {
                VStack(alignment: .leading, spacing: Theme.unit * 2) {
                    Text(session == nil ? (isCreating ? "Create your account" : "Sign in to Pond") : "Choose a Mac")
                        .font(.display)
                        .accessibilityAddTraits(.isHeader)
                    Text(session == nil ? "Use the same account as Pond on your Mac." : "Ripple opens the library on the Mac you pick.")
                        .foregroundStyle(Theme.muted)
                }
                .padding(.horizontal, Theme.gutter)
                if let session {
                    MachineList(machines: machines, onRetry: { Task { await loadMachines(session) } }) { machine in
                        open(machine, session)
                    }
                } else {
                    fields.padding(.horizontal, Theme.gutter)
                }
            }
            .padding(.top, Theme.unit * 12)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom) {
            if session == nil { actions }
        }
        .background(Theme.background)
        .toolbar(.hidden, for: .navigationBar)
        .animation(.snappy(duration: 0.2), value: failure)
        .animation(.snappy(duration: 0.2), value: session)
    }

    private var fields: some View {
        VStack(alignment: .leading, spacing: Theme.unit * 6) {
            field("Email") {
                TextField("Email", text: $email, prompt: Text("you@example.com").foregroundStyle(Theme.muted))
                    .keyboardType(.emailAddress)
                    .textContentType(.username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
            }
            field("Password") {
                SecureField("Password", text: $password, prompt: Text("At least 10 characters").foregroundStyle(Theme.muted))
                    .textContentType(isCreating ? .newPassword : .password)
                    .submitLabel(.go)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
            }
            if let failure {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
                    .font(.small)
                    .foregroundStyle(Theme.muted)
                    .transition(.opacity)
            }
        }
    }

    private func field(_ label: String, @ViewBuilder input: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: Theme.unit * 2) {
            Text(label).font(.textStrong)
            input()
                .font(.heading)
                .padding(.horizontal, Theme.unit * 3)
                .padding(.vertical, Theme.unit * 2)
                .frame(minHeight: Theme.rowHeight)
                .background(Theme.surface, in: .rect(cornerRadius: Theme.radiusControl))
                .overlay(RoundedRectangle(cornerRadius: Theme.radiusControl).strokeBorder(Theme.border, lineWidth: 0.5))
        }
    }

    private var actions: some View {
        VStack(spacing: Theme.unit * 2) {
            Button(action: submit) {
                HStack(spacing: Theme.unit * 2) {
                    if isWorking { ProgressView().tint(.white) }
                    Text(isWorking ? "Checking…" : isCreating ? "Create account" : "Sign in")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(ControlButtonStyle(isPrimary: true))
            .disabled(isWorking)
            Button(isCreating ? "I already have an account" : "Create an account") {
                isCreating.toggle()
                failure = nil
            }
            .font(.text)
            .foregroundStyle(Theme.muted)
            .frame(minHeight: Theme.rowHeight)
            NavigationLink("Use an address and token instead") {
                ConnectScreen(onConnect: onConnect)
            }
            .font(.small)
            .foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, Theme.gutter)
        .padding(.vertical, Theme.unit * 3)
        .background(Theme.background)
    }

    private func submit() {
        guard !isWorking else { return }
        let address = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard address.contains("@") else { return fail("Enter your email address.", .email) }
        guard password.count >= 10 else { return fail("Use a password of at least 10 characters.", .password) }
        isWorking = true
        failure = nil
        Task {
            defer { isWorking = false }
            do {
                let token = try await PondAccount.signIn(email: address, password: password, creating: isCreating, deviceName: UIDevice.current.name)
                password = ""
                await loadMachines(token)
                session = token
            } catch {
                fail(error.pondMessage, nil)
            }
        }
    }

    private func loadMachines(_ token: String) async {
        machines = (try? await PondAccount.machines(token: token)) ?? machines
        if machines.count == 1, let only = machines.first { open(only, token) }
    }

    private func open(_ machine: PondAccount.Machine, _ token: String) {
        let connection = PondAccount.connection(to: machine, token: token)
        do {
            try ConnectionStore.save(connection)
            onConnect(connection)
        } catch {
            fail(error.pondMessage, nil)
        }
    }

    private func fail(_ message: String, _ field: Field?) {
        failure = message
        focus = field
    }
}

private struct MachineList: View {
    let machines: [PondAccount.Machine]
    var onRetry: () -> Void
    var onPick: (PondAccount.Machine) -> Void

    var body: some View {
        if machines.isEmpty {
            StateMessage(
                title: "No Mac linked yet",
                detail: "Sign in to this account in Pond on your Mac, then check again.",
                actionTitle: "Check again",
                action: onRetry
            )
        } else {
            VStack(spacing: 0) {
                ForEach(machines) { machine in
                    Button { onPick(machine) } label: {
                        ListRow(title: machine.name, icon: "desktopcomputer", value: machine.online ? "Online" : "Offline", showsChevron: true)
                    }
                    .buttonStyle(RowPressStyle())
                    if machine.id != machines.last?.id { RowSeparator() }
                }
            }
        }
    }
}
