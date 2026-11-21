import Foundation
import UIKit

/// Turns a user photo into a cartoon mascot using a Gemini image model (plain REST, no SDK).
/// Key: https://aistudio.google.com/apikey. Note: Google may require a billing-enabled key for image models.
struct GeminiMascotService {
    enum MascotError: LocalizedError {
        case missingKey, badImage, http(Int, String), noImage

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Add a Gemini API key to create an AI mascot."
            case .badImage: return "Could not read that image."
            case .http(429, _): return "Gemini quota reached (image models may need a billing-enabled key). Try again later."
            case .http(let code, let msg): return "Gemini error \(code): \(msg)"
            case .noImage: return "Gemini did not return an image. Try a clearer photo."
            }
        }
    }

    /// Change here if Google retires or renames the image model.
    static let model = "gemini-2.5-flash-image"

    static let prompt = """
    Turn the subject of this photo into a cute, friendly cartoon pet mascot. \
    Keep the recognizable colors, fur/hair and accessories of the original. \
    Clean flat illustration style with a thick dark outline, front-facing, full body, \
    centered, square composition, on a plain solid light mint background. No text.
    """

    var apiKey: String

    /// Returns JPEG data of the generated mascot (max side 500).
    func generateMascot(from photoData: Data) async throws -> Data {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw MascotError.missingKey }
        guard UIImage(data: photoData) != nil else { throw MascotError.badImage }

        var request = URLRequest(url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(Self.model):generateContent")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-goog-api-key")
        let body: [String: Any] = [
            "contents": [[
                "parts": [
                    ["text": Self.prompt],
                    ["inline_data": ["mime_type": "image/jpeg", "data": photoData.base64EncodedString()]],
                ],
            ]],
            "generationConfig": ["responseModalities": ["TEXT", "IMAGE"]],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let msg = (try? JSONDecoder().decode(APIError.self, from: data))?.error.message
                ?? String(data: data, encoding: .utf8) ?? ""
            throw MascotError.http(status, msg)
        }

        let decoded = try JSONDecoder().decode(GenerateResponse.self, from: data)
        for part in decoded.candidates?.first?.content?.parts ?? [] {
            if let b64 = (part.inlineData ?? part.inline_data)?.data,
               let bytes = Data(base64Encoded: b64),
               let image = UIImage(data: bytes),
               let jpeg = Self.resized(image, maxSide: 500).jpegData(compressionQuality: 0.85) {
                return jpeg
            }
        }
        throw MascotError.noImage
    }

    private static func resized(_ image: UIImage, maxSide: CGFloat) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private struct APIError: Decodable {
        struct Inner: Decodable { let message: String }
        let error: Inner
    }

    private struct GenerateResponse: Decodable {
        struct InlineData: Decodable { let data: String }
        struct Part: Decodable {
            let inlineData: InlineData?
            let inline_data: InlineData?
        }
        struct Content: Decodable { let parts: [Part]? }
        struct Candidate: Decodable { let content: Content? }
        let candidates: [Candidate]?
    }
}
