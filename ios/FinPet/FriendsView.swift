import SwiftUI
import Pow

/// Friends tab: real friends from the server, a notifications dropdown for incoming requests (accept / deny),
/// adding a friend by username (sends a request, never adds directly) and removing friends.
struct FriendsView: View {
    @EnvironmentObject private var auth: AuthSession
    @Environment(\.mascotPalette) private var palette
    @StateObject private var store = FriendsStore()
    @AppStorage("finpet.ref.checkins") private var checkins = ""
    @State private var showNotifications = false
    @State private var adding = false
    @State private var username = ""
    @State private var pendingRemoval: Friend?

    var body: some View {
        VStack(alignment: .leading, spacing: 19) {
            header
            if showNotifications { notifications }
            if let message = store.message {
                Text(message).font(.footnote.weight(.semibold)).foregroundStyle(muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text("Shared streaks").font(.system(.title2, design: .serif, weight: .semibold))
            if store.friends.isEmpty {
                Text(store.loading ? "Loading…" : "No friends yet. Add a friend by username to start a shared streak.")
                    .font(.subheadline).foregroundStyle(muted)
            } else {
                VStack(spacing: 0) {
                    ForEach(store.friends) { friend in
                        friendRow(friend)
                        Divider()
                    }
                }
            }
            if !store.outgoing.isEmpty {
                Text("Waiting for \(store.outgoing.map(\.username).joined(separator: ", ")) to accept")
                    .font(.footnote).foregroundStyle(muted)
            }
            Button { adding = true } label: {
                Label("Add friend", systemImage: "plus").font(.subheadline.weight(.semibold)).frame(minHeight: 44)
            }.buttonStyle(.plain).foregroundStyle(palette.accent)
        }
        .task { await store.refresh(auth: auth) }
        .refreshable { await store.refresh(auth: auth) }
        .alert("Add a friend", isPresented: $adding) {
            TextField("Username", text: $username)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Button("Add friend") {
                let name = username
                username = ""
                Task { _ = await store.sendRequest(to: name, auth: auth) }
            }
            Button("Cancel", role: .cancel) { username = "" }
        } message: {
            Text("Enter their FinPet username. They become your friend once they accept your request.")
        }
        .confirmationDialog("Remove \(pendingRemoval?.username ?? "friend")?", isPresented: Binding(
            get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } }
        ), titleVisibility: .visible) {
            Button("Remove friend", role: .destructive) {
                if let friend = pendingRemoval { Task { await store.remove(friend, auth: auth) } }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: {
            Text("You will both be removed from each other's friends lists and your shared streak ends.")
        }
    }

    private var header: some View {
        HStack {
            Text("Friends").font(.system(.largeTitle, design: .serif, weight: .semibold))
            Spacer()
            Button {
                withAnimation(.snappy) { showNotifications.toggle() }
                if showNotifications { Task { await store.refresh(auth: auth) } }
            } label: {
                Image(systemName: store.incoming.isEmpty ? "bell" : "bell.badge.fill")
                    .frame(width: 44, height: 44)
                    .background(palette.panel, in: Circle())
                    .overlay(alignment: .topTrailing) {
                        if !store.incoming.isEmpty {
                            Text("\(store.incoming.count)").font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                                .background(.red, in: Capsule())
                        }
                    }
            }
            .buttonStyle(.plain).foregroundStyle(palette.accent)
            .accessibilityLabel("Notifications")
            .accessibilityValue(store.incoming.isEmpty ? "none" : "\(store.incoming.count) friend requests")
            Menu {
                Button("Log out", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) { auth.logOut() }
            } label: {
                Image(systemName: "ellipsis").frame(width: 44, height: 44).foregroundStyle(palette.accent)
            }.accessibilityLabel("Account options")
        }
    }

    private var notifications: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Friend requests").font(.headline).padding(.bottom, 8)
            if store.incoming.isEmpty {
                Text("No new requests.").font(.subheadline).foregroundStyle(muted)
            }
            ForEach(store.incoming) { request in
                HStack(spacing: 10) {
                    Text(request.username).font(.subheadline.weight(.semibold))
                    Spacer(minLength: 6)
                    Button("Deny") { Task { await store.deny(request, auth: auth) } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(muted)
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .background(.white, in: RoundedRectangle(cornerRadius: 8))
                    Button("Accept") { Task { await store.accept(request, auth: auth) } }
                        .font(.footnote.weight(.semibold)).foregroundStyle(.white)
                        .padding(.horizontal, 12).frame(minHeight: 34)
                        .background(palette.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).padding(.vertical, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14).background(palette.panel, in: RoundedRectangle(cornerRadius: 14))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private func friendRow(_ friend: Friend) -> some View {
        let checked = checkins.split(separator: "|").contains(Substring(friend.username))
        return HStack(spacing: 12) {
            Pet(color: .leaf).frame(width: 50, height: 50).background(palette.panel, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(friend.username).font(.headline)
                Text(checked ? "You checked in" : "Waiting for a check-in").font(.footnote).foregroundStyle(muted)
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 5) {
                Label("\(friend.streak)", systemImage: "flame.fill")
                    .font(.footnote.monospacedDigit().weight(.semibold)).foregroundStyle(muted)
                Button {
                    checkins += checkins.isEmpty ? friend.username : "|" + friend.username
                } label: {
                    Text(checked ? "Done" : "Check in").font(.footnote.weight(.semibold))
                        .padding(.horizontal, 10).frame(minHeight: 32)
                        .background(palette.panel, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain).foregroundStyle(palette.accent).disabled(checked)
                .changeEffect(.feedback(hapticNotification: .success), value: checked, isEnabled: checked)
            }
            Menu {
                Button("Remove friend", systemImage: "person.badge.minus", role: .destructive) { pendingRemoval = friend }
            } label: {
                Image(systemName: "ellipsis").frame(width: 36, height: 44).foregroundStyle(muted)
            }.accessibilityLabel("Options for \(friend.username)")
        }.padding(.vertical, 10)
    }
}
