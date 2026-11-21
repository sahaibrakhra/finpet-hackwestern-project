import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var auth: AuthSession
    @State private var creating = false
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var loading = false
    @FocusState private var focus: Field?
    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("FinPet").font(.system(size: 34, weight: .heavy)).foregroundStyle(ink)
                Text(creating ? "Create an account to get started." : "Welcome back. Log in to continue.")
                    .font(.subheadline).foregroundStyle(muted)

                Picker("Mode", selection: $creating) {
                    Text("Log in").tag(false)
                    Text("Create account").tag(true)
                }
                .pickerStyle(.segmented)
                .onChange(of: creating) { _, _ in error = nil }

                VStack(alignment: .leading, spacing: 12) {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focus, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focus = .password }
                        .padding(12).background(cream, in: RoundedRectangle(cornerRadius: 12))
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                        .focused($focus, equals: .password)
                        .submitLabel(.go)
                        .onSubmit { submit() }
                        .padding(12).background(cream, in: RoundedRectangle(cornerRadius: 12))
                    if creating {
                        Text("Username: 3-20 letters, numbers, or underscores. Password: 8-72 characters.")
                            .font(.footnote).foregroundStyle(muted)
                    }
                }
                .petCard()

                if let error {
                    Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                        .accessibilityLabel("Error: \(error)")
                }

                ZStack {
                    ActionButton(title: creating ? "Create account" : "Log in") { submit() }
                        .disabled(loading).opacity(loading ? 0.6 : 1)
                    if loading { ProgressView().tint(.white) }
                }
            }
            .padding(24)
        }
        .scrollDismissesKeyboard(.interactively)
        .background(cream.ignoresSafeArea())
        .foregroundStyle(ink)
    }

    private func submit() {
        guard !loading else { return }
        error = nil
        loading = true
        focus = nil
        Task {
            do {
                try await auth.submit(username: username, password: password, create: creating)
            } catch let failure {
                error = failure.localizedDescription
            }
            loading = false
        }
    }
}
