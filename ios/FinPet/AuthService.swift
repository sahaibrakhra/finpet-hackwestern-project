import Foundation
import Security

struct AuthUser: Codable, Equatable {
    let id: String
    let username: String
}

private struct AuthResponse: Decodable {
    let token: String
    let expires_at: String
    let user: AuthUser
}

/// Token + expiry stored as one Keychain item (never UserDefaults).
struct StoredSession: Codable {
    var token: String
    var expiresAt: Date
    var user: AuthUser? = nil
}

enum AuthKeychain {
    private static let service = "ca.hackwestern.finpet.auth"
    private static let account = "session"

    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: account]
    }

    enum ReadResult {
        case found(StoredSession)
        case missing
        case unavailable(OSStatus)
    }

    static func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let changes = [kSecValueData as String: data]
        let update = SecItemUpdate(query as CFDictionary, changes as CFDictionary)
        if update == errSecSuccess { return }
        guard update == errSecItemNotFound else { throw storageError(update) }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else { throw storageError(add) }
    }

    static func load() -> ReadResult {
        var item = query
        item[kSecReturnData as String] = true
        item[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(item as CFDictionary, &result)
        if status == errSecItemNotFound { return .missing }
        guard status == errSecSuccess else { return .unavailable(status) }
        guard let data = result as? Data,
              let session = try? JSONDecoder().decode(StoredSession.self, from: data) else { return .missing }
        return .found(session)
    }

    private static func storageError(_ status: OSStatus) -> AuthError {
        .message("FinPet couldn’t save your sign-in to Keychain (\(status)). Please try again.")
    }

    static func clear() { SecItemDelete(query as CFDictionary) }
}

enum AuthError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

/// Holds the signed-in state for the app. Avatars stay per-device and are not tied to the account.
@MainActor
final class AuthSession: ObservableObject {
    enum State { case checking, signedOut, signedIn(AuthUser?) }

    @Published private(set) var state: State = .checking
    private var token: String?

    init() { restore() }

    func restore() {
        guard case .checking = state else { return }
        switch AuthKeychain.load() {
        case .found(let stored) where stored.expiresAt > Date():
            token = stored.token
            state = .signedIn(stored.user)
            Task { await validate(stored.token) }
        case .found:
            AuthKeychain.clear()
            state = .signedOut
        case .missing:
            state = .signedOut
        case .unavailable(let status):
            // A locked device can temporarily block Keychain access.
            if status != errSecInteractionNotAllowed && status != errSecNotAvailable {
                state = .signedOut
            }
        }
    }

    nonisolated static func validate(username: String, password: String) -> String? {
        if username.count < 3 || username.count > 20 { return "Username must be 3-20 characters." }
        if username.contains(where: { !($0.isASCII && ($0.isLetter || $0.isNumber || $0 == "_")) }) {
            return "Username can only use letters, numbers, and underscores."
        }
        if password.count < 8 || password.count > 72 { return "Password must be 8-72 characters." }
        return nil
    }

    func submit(username: String, password: String, create: Bool) async throws {
        let name = username.trimmingCharacters(in: .whitespaces)
        if let problem = Self.validate(username: name, password: password) { throw AuthError.message(problem) }
        var request = URLRequest(url: MascotService.baseURL.appendingPathComponent(create ? "api/auth/register" : "api/auth/login"))
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["username": name, "password": password])
        let data: Data
        let response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw AuthError.message("Could not reach the FinPet server. Check your connection.") }
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AuthError.message(Self.detail(data)) }
        guard let auth = try? JSONDecoder().decode(AuthResponse.self, from: data),
              let expires = Self.parseDate(auth.expires_at) else {
            throw AuthError.message("Unexpected response from the server.")
        }
        try AuthKeychain.save(StoredSession(token: auth.token, expiresAt: expires, user: auth.user))
        token = auth.token
        state = .signedIn(auth.user)
    }

    func logOut() {
        AuthKeychain.clear()
        token = nil
        state = .signedOut
    }

    /// Clears the stored token if the server rejects it; network failures keep the session (offline use).
    private func validate(_ checked: String) async {
        var request = URLRequest(url: MascotService.baseURL.appendingPathComponent("api/auth/me"))
        request.timeoutInterval = 15
        request.setValue("Bearer \(checked)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, token == checked else { return }
        if http.statusCode == 401 {
            logOut()
        } else if http.statusCode == 200, let user = try? JSONDecoder().decode(AuthUser.self, from: data) {
            state = .signedIn(user)
        }
    }

    private static func detail(_ data: Data) -> String {
        struct Body: Decodable { let detail: String }
        if let body = try? JSONDecoder().decode(Body.self, from: data) { return body.detail }
        return "Something went wrong. Please try again."
    }

    private static func parseDate(_ text: String) -> Date? {
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFraction.date(from: text) { return date }
        if let date = ISO8601DateFormatter().date(from: text) { return date }
        // Backend may emit a naive UTC timestamp without a zone suffix.
        let naive = DateFormatter()
        naive.locale = Locale(identifier: "en_US_POSIX")
        naive.timeZone = TimeZone(identifier: "UTC")
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss"] {
            naive.dateFormat = format
            if let date = naive.date(from: text) { return date }
        }
        return nil
    }
}
