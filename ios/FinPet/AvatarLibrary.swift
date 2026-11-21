import SwiftUI
import Observation

enum PetMood: String, CaseIterable, Codable {
    case idle, wave, dance, cry

    var title: String {
        switch self {
        case .idle: "Idle"
        case .wave: "Wave"
        case .dance: "Dance"
        case .cry: "Sad"
        }
    }

    /// Idle and sad play back and forth forever; wave and dance play once.
    var loops: Bool { self == .idle || self == .cry }
}

enum AnimationStatus: Equatable {
    case running
    case done
    case failed(String)
}

struct AvatarClip {
    let frames: [UIImage]
    let fps: Double
    var duration: Double { Double(frames.count) / max(fps, 1) }
}

/// Every avatar the user has created, with its animations, saved on disk so switching between avatars
/// never re-generates (and re-pays for) anything.
///
/// Documents/FinPetAvatars/index.json
/// Documents/FinPetAvatars/<id>/avatar.png
/// Documents/FinPetAvatars/<id>/<mood>/frame_000.png ... and meta.json (written last = "clip is complete")
@Observable @MainActor
final class AvatarLibrary {
    static let shared = AvatarLibrary()

    struct Entry: Codable, Identifiable, Equatable {
        let id: String
        let createdAt: Date
        /// "#RRGGBB" of the background Gemini drew behind the avatar.
        let background: String
    }

    private struct Index: Codable {
        var entries: [Entry]
        var activeID: String?
    }

    private struct ClipMeta: Codable {
        let fps: Double
        let count: Int
    }

    private(set) var entries: [Entry] = []
    private(set) var activeID: String?
    private(set) var status: [String: [PetMood: AnimationStatus]] = [:]

    @ObservationIgnored private var clipCache: [String: AvatarClip] = [:]
    private let root: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        root = docs.appendingPathComponent("FinPetAvatars", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        if let data = try? Data(contentsOf: root.appendingPathComponent("index.json")),
           let index = try? JSONDecoder().decode(Index.self, from: data) {
            entries = index.entries.filter { FileManager.default.fileExists(atPath: avatarURL($0.id).path) }
            activeID = entries.contains { $0.id == index.activeID } ? index.activeID : nil
        }
    }

    // MARK: - Reading

    var active: Entry? { entries.first { $0.id == activeID } }

    /// The tint for the mascot stage: the background color of the active avatar, if any.
    var activeBackground: Color? { active.flatMap { Color(hex: $0.background) } }

    func avatarData(_ id: String) -> Data? { try? Data(contentsOf: avatarURL(id)) }

    func hasAnimation(_ id: String, _ mood: PetMood) -> Bool {
        FileManager.default.fileExists(atPath: clipURL(id, mood).appendingPathComponent("meta.json").path)
    }

    func state(_ id: String, _ mood: PetMood) -> AnimationStatus? {
        hasAnimation(id, mood) ? .done : status[id]?[mood]
    }

    func missingAnimations(_ id: String) -> [PetMood] {
        PetMood.allCases.filter { !hasAnimation(id, $0) }
    }

    /// Loads (and caches) the saved clip. Returns nil if that animation was never generated.
    func clip(id: String, mood: PetMood) -> AvatarClip? {
        let key = "\(id)/\(mood.rawValue)"
        if let cached = clipCache[key] { return cached }
        let dir = clipURL(id, mood)
        guard let metaData = try? Data(contentsOf: dir.appendingPathComponent("meta.json")),
              let meta = try? JSONDecoder().decode(ClipMeta.self, from: metaData) else { return nil }
        let frames = (0..<meta.count).compactMap {
            UIImage(contentsOfFile: dir.appendingPathComponent(String(format: "frame_%03d.png", $0)).path)
        }
        guard !frames.isEmpty else { return nil }
        let clip = AvatarClip(frames: frames, fps: meta.fps)
        clipCache[key] = clip
        return clip
    }

    // MARK: - Writing

    @discardableResult
    func create(avatarPNG: Data, background: String) -> Entry {
        let entry = Entry(id: UUID().uuidString, createdAt: Date(), background: background)
        try? FileManager.default.createDirectory(at: avatarURL(entry.id).deletingLastPathComponent(), withIntermediateDirectories: true)
        try? avatarPNG.write(to: avatarURL(entry.id))
        entries.insert(entry, at: 0)
        activeID = entry.id
        clipCache.removeAll()
        saveIndex()
        return entry
    }

    func setActive(_ id: String?) {
        activeID = id
        clipCache.removeAll()
        saveIndex()
    }

    func delete(_ id: String) {
        try? FileManager.default.removeItem(at: root.appendingPathComponent(id, isDirectory: true))
        entries.removeAll { $0.id == id }
        status[id] = nil
        if activeID == id { activeID = nil }
        clipCache.removeAll()
        saveIndex()
    }

    /// Generates only the animations this avatar does not have yet (each is one paid video call),
    /// all at once. Runs in the library, so closing the editor does not cancel (and waste) them.
    func generateMissingAnimations(for id: String) {
        guard let entry = entries.first(where: { $0.id == id }), let png = avatarData(id) else { return }
        for mood in missingAnimations(id) where status[id]?[mood] != .running {
            status[id, default: [:]][mood] = .running
            Task {
                do {
                    let animation = try await MascotService().generateAnimation(
                        kind: mood.rawValue, avatarPNG: png, background: entry.background)
                    guard entries.contains(where: { $0.id == id }) else { return }
                    try save(animation, id: id, mood: mood)
                    status[id]?[mood] = .done
                } catch {
                    status[id]?[mood] = .failed(error.localizedDescription)
                }
            }
        }
    }

    // MARK: - Disk

    private func avatarURL(_ id: String) -> URL {
        root.appendingPathComponent(id, isDirectory: true).appendingPathComponent("avatar.png")
    }

    private func clipURL(_ id: String, _ mood: PetMood) -> URL {
        root.appendingPathComponent(id, isDirectory: true).appendingPathComponent(mood.rawValue, isDirectory: true)
    }

    private func save(_ animation: MascotService.Animation, id: String, mood: PetMood) throws {
        let dir = clipURL(id, mood)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (index, frame) in animation.frames.enumerated() {
            try frame.write(to: dir.appendingPathComponent(String(format: "frame_%03d.png", index)))
        }
        let meta = try JSONEncoder().encode(ClipMeta(fps: animation.fps, count: animation.frames.count))
        try meta.write(to: dir.appendingPathComponent("meta.json"))
    }

    private func saveIndex() {
        let index = Index(entries: entries, activeID: activeID)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: root.appendingPathComponent("index.json"))
        }
    }
}

extension Color {
    /// "#RRGGBB" (or "RRGGBB") -> Color; nil if it is not valid hex.
    init?(hex: String) {
        let value = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(red: Double((number >> 16) & 0xFF) / 255,
                  green: Double((number >> 8) & 0xFF) / 255,
                  blue: Double(number & 0xFF) / 255)
    }
}
