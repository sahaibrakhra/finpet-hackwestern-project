import Foundation
import UIKit
import Vision
import CoreImage

/// Sends the user's photo to the FinPet backend, which asks Gemini for a full-body cartoon avatar.
/// The Gemini key lives only on the backend (backend/.env); the app never sees it.
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

    /// Backend base URL. Set `FinPetBackendURL` in ios/Info.plist (use your computer's LAN IP on a real device).
    static var baseURL: URL {
        let configured = Bundle.main.object(forInfoDictionaryKey: "FinPetBackendURL") as? String
        return URL(string: configured ?? "") ?? URL(string: "http://localhost:8000")!
    }

    /// Returns PNG data (transparent background when it can be cut out on-device) of the full-body avatar.
    func generateAvatar(from photoData: Data) async throws -> Data {
        guard UIImage(data: photoData) != nil else { throw MascotError.badImage }

        let boundary = "finpet-\(UUID().uuidString)"
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(photoData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        var request = URLRequest(url: Self.baseURL.appendingPathComponent("api/avatar"))
        request.httpMethod = "POST"
        request.timeoutInterval = 150
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

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
            let detail = (try? JSONDecoder().decode(ServerError.self, from: data))?.detail
            throw MascotError.server(detail ?? "Server error (\(status)).")
        }
        guard let image = UIImage(data: data) else { throw MascotError.badImage }

        let finalImage = Self.removeBackground(from: image) ?? image
        guard let png = finalImage.pngData() else { throw MascotError.badImage }
        return png
    }

    /// Cuts out the subject with Vision (iOS 17+). Returns nil if it fails (e.g. on some simulators),
    /// in which case the generated image is used as-is on its plain background.
    private static func removeBackground(from image: UIImage) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        do {
            try handler.perform([request])
            guard let result = request.results?.first else { return nil }
            let buffer = try result.generateMaskedImage(ofInstances: result.allInstances,
                                                        from: handler, croppedToInstancesExtent: true)
            let ci = CIImage(cvPixelBuffer: buffer)
            guard let out = CIContext().createCGImage(ci, from: ci.extent) else { return nil }
            return UIImage(cgImage: out)
        } catch {
            return nil
        }
    }

    private struct ServerError: Decodable { let detail: String }
}
