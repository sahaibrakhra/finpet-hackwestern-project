import SwiftUI

/// Plays the saved animation for `mood` on the active avatar. Falls back to the idle clip, then to the
/// still image, so it always shows something.
struct AnimatedAvatar: View {
    let mood: PetMood
    let fallback: UIImage
    let accessory: String
    @State private var start = Date()

    var body: some View {
        let library = AvatarLibrary.shared
        let resolved = resolve(library)
        Group {
            if let resolved {
                TimelineView(.animation) { context in
                    let index = frameIndex(resolved, at: context.date)
                    framed(resolved.clip.frames[index], pose: resolved.clip.accessoryPoses[index])
                }
            } else {
                framed(fallback, pose: AccessoryPose(image: fallback))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: mood) { _, _ in start = Date() }
    }

    private func framed(_ image: UIImage, pose: AccessoryPose) -> some View {
        Image(uiImage: image).resizable().scaledToFit()
            .overlay { MascotAccessory(name: accessory, pose: pose, generated: true) }
    }

    private func resolve(_ library: AvatarLibrary) -> (clip: AvatarClip, mood: PetMood)? {
        guard let id = library.activeID else { return nil }
        if let clip = library.clip(id: id, mood: mood) { return (clip, mood) }
        if let clip = library.clip(id: id, mood: .idle) { return (clip, .idle) }
        return nil
    }

    private func frameIndex(_ resolved: (clip: AvatarClip, mood: PetMood), at date: Date) -> Int {
        let count = resolved.clip.frames.count
        let step = Int(max(0, date.timeIntervalSince(start)) * resolved.clip.fps)
        guard count > 1 else { return 0 }
        if resolved.mood.loops {
            // Back and forth so a clip that does not loop on its own never visibly jumps.
            let period = 2 * (count - 1)
            let position = step % period
            return position < count ? position : period - position
        }
        return min(step, count - 1)
    }
}
