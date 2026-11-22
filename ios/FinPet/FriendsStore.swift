import Foundation

struct Friend: Decodable, Identifiable, Equatable {
    let id: String
    let username: String
    let streak: Int
}

/// A pending request. `request_id` identifies the request; `id`/`username` are the other person.
struct FriendRequest: Decodable, Identifiable, Equatable {
    let request_id: String
    let id: String
    let username: String
    var requestID: String { request_id }
}

private struct FriendsOverview: Decodable {
    let friends: [Friend]
    let incoming: [FriendRequest]
    let outgoing: [FriendRequest]
}

/// Talks to /api/friends. Requests are only sent to people who really have an account; a friend is added
/// on both sides only once the other person accepts.
@MainActor
final class FriendsStore: ObservableObject {
    @Published private(set) var friends: [Friend] = []
    @Published private(set) var incoming: [FriendRequest] = []
    @Published private(set) var outgoing: [FriendRequest] = []
    @Published private(set) var loading = false
    /// Shown to the user; cleared on the next successful action.
    @Published var message: String?

    func refresh(auth: AuthSession) async {
        loading = true
        defer { loading = false }
        guard let data = await call("api/friends", method: "GET", body: nil, auth: auth, quiet: true),
              let overview = try? JSONDecoder().decode(FriendsOverview.self, from: data) else { return }
        friends = overview.friends
        incoming = overview.incoming
        outgoing = overview.outgoing
    }

    /// Returns true if the request was sent.
    func sendRequest(to username: String, auth: AuthSession) async -> Bool {
        let name = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { message = "Enter a username."; return false }
        guard await call("api/friends/requests", method: "POST", body: ["username": name], auth: auth) != nil else { return false }
        message = "Friend request sent to \(name.lowercased())."
        await refresh(auth: auth)
        return true
    }

    func accept(_ request: FriendRequest, auth: AuthSession) async {
        guard await call("api/friends/requests/\(request.requestID)/accept", method: "POST", body: [:], auth: auth) != nil else { return }
        message = nil
        await refresh(auth: auth)
    }

    func deny(_ request: FriendRequest, auth: AuthSession) async {
        guard await call("api/friends/requests/\(request.requestID)/deny", method: "POST", body: [:], auth: auth) != nil else { return }
        message = nil
        await refresh(auth: auth)
    }

    func remove(_ friend: Friend, auth: AuthSession) async {
        guard await call("api/friends/\(friend.id)", method: "DELETE", body: nil, auth: auth) != nil else { return }
        message = nil
        await refresh(auth: auth)
    }

    /// Returns the response body on success. On failure sets `message` (unless `quiet`) and returns nil.
    private func call(_ path: String, method: String, body: [String: String]?, auth: AuthSession, quiet: Bool = false) async -> Data? {
        guard let token = auth.bearerToken else { return nil }
        var request = URLRequest(url: MascotService.baseURL.appendingPathComponent(path))
        request.httpMethod = method
        request.timeoutInterval = 15
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch {
            if !quiet { message = "Could not reach the FinPet server. Check your connection." }
            return nil
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 { auth.logOut(); return nil }
        guard status == 200 else {
            if !quiet {
                struct Body: Decodable { let detail: String }
                message = (try? JSONDecoder().decode(Body.self, from: data))?.detail ?? "Something went wrong. Please try again."
            }
            return nil
        }
        return data
    }
}
