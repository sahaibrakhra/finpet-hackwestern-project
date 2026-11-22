import Foundation
import UIKit

/// Talks to the FinPet backend, which holds the Gemini key and does all the Gemini calls.
/// The app never sees an API key.
struct MascotService {
    enum MascotError: LocalizedError {
        case badImage, server(String), unreachable

        var errorDescription: String? {
            switch self {
            case .badImage: return "Could not read that image."
            case .server(let message): return message
            case .unreachable: return "Could not reach the FinPet server. Is the backend running?"
            }
        }
    }

    struct Avatar {
        /// Transparent full-body PNG (9:16).
        let png: Data
        /// Background color Gemini drew behind the avatar, as "#RRGGBB". The app tints its stage with it.
        let background: String
    }

    struct Animation {
        let fps: Double
        /// Transparent PNG frames, same canvas as the avatar.
        let frames: [Data]
    }

    /// Use the configured LAN address on the simulator and physical devices.
    static var baseURL: URL {
        let local = URL(string: "http://localhost:8000")!
        guard let configured = Bundle.main.object(forInfoDictionaryKey: "FinPetBackendURL") as? String,
              let url = URL(string: configured), url.host != nil else { return local }
        return url
    }

    /// Uploads the photo; the server asks Gemini for a full-body avatar and cuts out its background.
    func generateAvatar(from photoData: Data) async throws -> Avatar {
        guard UIImage(data: photoData) != nil else { throw MascotError.badImage }
        var form = MultipartForm()
        form.addFile(name: "photo", filename: "photo.jpg", mimeType: "image/jpeg", data: photoData)
        let data = try await send(path: "api/avatar", form: form, timeout: 150)
        struct Payload: Decodable { let avatar: Data; let background: String }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            throw MascotError.server("Unexpected response from the server.")
        }
        return Avatar(png: payload.avatar, background: payload.background)
    }

    /// Asks the server for one short animation (`idle`, `wave`, `dance` or `cry`) of an existing avatar.
    /// This is a paid Gemini video call, so callers should only request clips they do not already have.
    func generateAnimation(kind: String, avatarPNG: Data, background: String) async throws -> Animation {
        var form = MultipartForm()
        form.addField(name: "kind", value: kind)
        form.addField(name: "background", value: background)
        form.addFile(name: "avatar", filename: "avatar.png", mimeType: "image/png", data: avatarPNG)
        let data = try await send(path: "api/animate", form: form, timeout: 420)
        struct Payload: Decodable { let fps: Double; let frames: [Data] }
        guard let payload = try? JSONDecoder().decode(Payload.self, from: data), !payload.frames.isEmpty else {
            throw MascotError.server("Unexpected response from the server.")
        }
        return Animation(fps: payload.fps, frames: payload.frames)
    }

    private func send(path: String, form: MultipartForm, timeout: TimeInterval) async throws -> Data {
        var request = URLRequest(url: Self.baseURL.appendingPathComponent(path))
        request.httpMethod = "POST"
        request.timeoutInterval = timeout
        request.setValue("multipart/form-data; boundary=\(form.boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = form.finalized()

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw MascotError.unreachable
        }

        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            struct ServerError: Decodable { let detail: String }
            let detail = (try? JSONDecoder().decode(ServerError.self, from: data))?.detail
            throw MascotError.server(detail ?? "Server error (\(status)).")
        }
        return data
    }
}

private struct MultipartForm {
    let boundary = "finpet-\(UUID().uuidString)"
    private var body = Data()

    mutating func addField(name: String, value: String) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
        body.append(Data("\(value)\r\n".utf8))
    }

    mutating func addFile(name: String, filename: String, mimeType: String, data: Data) {
        body.append(Data("--\(boundary)\r\n".utf8))
        body.append(Data("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n".utf8))
        body.append(Data("Content-Type: \(mimeType)\r\n\r\n".utf8))
        body.append(data)
        body.append(Data("\r\n".utf8))
    }

    func finalized() -> Data {
        var out = body
        out.append(Data("--\(boundary)--\r\n".utf8))
        return out
    }
}
