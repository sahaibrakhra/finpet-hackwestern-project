import SwiftUI
import Pow

struct LoginView: View {
    @EnvironmentObject private var auth: AuthSession
    @Environment(\.mascotPalette) private var palette
    @State private var creating = false
    @State private var username = ""
    @State private var password = ""
    @State private var error: String?
    @State private var loading = false
    @FocusState private var focus: Field?
    private enum Field { case username, password }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("FinPet")
                            .font(.system(size: 51, weight: .semibold, design: .serif))
                            .accessibilityAddTraits(.isHeader)
                        Text("A little money practice.").font(.subheadline).foregroundStyle(muted)
                    }
                    Spacer(minLength: 7)
                    Pet(color: .leaf).frame(width: 102, height: 102)
                }
                .padding(.horizontal, 25).padding(.vertical, 22)
                .frame(maxWidth: .infinity)
                .background(palette.stage)

                VStack(alignment: .leading, spacing: 19) {
                    HStack(spacing: 23) {
                        modeButton("Log in", create: false)
                        modeButton("Create account", create: true)
                        Spacer(minLength: 0)
                    }
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
                    .changeEffect(.feedbackHapticSelection, value: creating)
                    .onChange(of: creating) { _, _ in error = nil }

                    VStack(alignment: .leading, spacing: 13) {
                        credentialField("Username") {
                            TextField("Enter username", text: $username)
                                .textContentType(.username)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                .focused($focus, equals: .username)
                                .submitLabel(.next)
                                .onSubmit { focus = .password }
                        }
                        credentialField("Password") {
                            SecureField("Enter password", text: $password)
                                .textContentType(creating ? .newPassword : .password)
                                .focused($focus, equals: .password)
                                .submitLabel(.go)
                                .onSubmit { submit() }
                        }
                        if creating {
                            Text("Username: 3–20 letters, numbers, or underscores. Password: 8–72 characters.")
                                .font(.footnote).foregroundStyle(muted)
                        }
                    }
                    if let error {
                        Text(error).font(.subheadline.weight(.semibold)).foregroundStyle(.red)
                            .accessibilityLabel("Error: \(error)")
                    }
                    ZStack {
                        ActionButton(title: creating ? "Create account" : "Log in") { submit() }
                            .disabled(loading).opacity(loading ? 0.6 : 1)
                        if loading { ProgressView().tint(.white) }
                    }
                }.padding(.horizontal, 25).padding(.top, 19).padding(.bottom, 24)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(palette.paper.ignoresSafeArea())
        .foregroundStyle(ink)
    }

    private func modeButton(_ title: String, create: Bool) -> some View {
        let current = creating == create
        return Button { creating = create } label: {
            Text(title).font(.headline.weight(current ? .semibold : .regular))
                .foregroundStyle(current ? palette.accent : muted)
                .frame(minHeight: 44)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(current ? palette.accent : .clear).frame(height: 2)
                }
        }.buttonStyle(.plain)
            .accessibilityAddTraits(current ? .isSelected : [])
    }

    private func credentialField<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.subheadline.weight(.semibold))
            content()
                .accessibilityLabel(title)
                .frame(minHeight: 43)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.rule).frame(height: 1) }
        }
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
