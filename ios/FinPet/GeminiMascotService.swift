import Foundation
import UIKit
import Vision
import CoreImage

/// Turns a user photo into a full-body cartoon avatar using a Gemini image model (plain REST, no SDK).
/// Requires a billing-enabled key from https://aistudio.google.com/apikey (image models are not on the free tier).
struct GeminiMascotService {
    enum MascotError: LocalizedError {
        case missingKey, badImage, http(Int, String), noImage(String)

        var errorDescription: String? {
            switch self {
            case .missingKey: return "Add your Gemini API key to create an avatar."
            case .badImage: return "Could not read that image."
            case .http(429, _): return "Gemini rate limit or quota reached. Try again shortly."
            case .http(let code, let msg): return "Gemini error \(code): \(msg)"
            case .noImage(let note): return note.isEmpty ? "Gemini did not return an image. Try a clearer photo." : "Gemini did not return an image: \(note)"
            }
        }
    }

    /// Change here if Google retires or renames the image model.
    static let model = "gemini-3.1-flash-image"

    static let prompt = """
    Create a full-body cartoon avatar of the subject in this photo. \
    Show the entire body from head to toe, standing in a relaxed neutral front-facing pose, \
    with both feet visible and nothing cropped. \
    Preserve the subject's recognizable features: face, hairstyle or fur, skin tone, \
    colors and clothing or accessories (or a faithful cartoon version of the creature or object if it is not a person). \
    Cute, friendly, clean flat illustration style with a thick dark outline. \
    Centered, plain solid white background, no shadows, no props, no text.
    """

    var apiKey: String

    /// Returns PNG data (transparent background when it can be cut out on-device) of the full-body avatar, max side 600.
    func generateAvatar(from photoData: Data) async throws -> Data {
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
        var note = ""
        for part in decoded.candidates?.first?.content?.parts ?? [] {
            if let text = part.text { note += text }
            if let b64 = (part.inlineData ?? part.inline_data)?.data,
               let bytes = Data(base64Encoded: b64),
               let image = UIImage(data: bytes) {
                let small = Self.resized(image, maxSide: 600)
                let finalImage = Self.removeBackground(from: small) ?? small
                if let png = finalImage.pngData() { return png }
            }
        }
        throw MascotError.noImage(note)
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
            let text: String?
        }
        struct Content: Decodable { let parts: [Part]? }
        struct Candidate: Decodable { let content: Content? }
        let candidates: [Candidate]?
    }
}
