import SwiftUI

/// Plays the saved animation for `mood` on the active avatar. Falls back to the idle clip, then to the
/// still image, so it always shows something.
///
/// Every image (still or clip frame) is drawn with its HEIGHT equal to the box, so the avatar is the same
/// size in all of them. New clips are 16:9, wider than the box: the extra width runs past the box and is
/// cut off by the stage's own edge, so an arm swinging wide is never chopped in the middle of the screen.
struct AnimatedAvatar: View {
    let mood: PetMood
    let fallback: UIImage
    @State private var start = Date()

    var body: some View {
        let library = AvatarLibrary.shared
        let resolved = resolve(library)
        // The overlay does not affect the layout size, so wide frames can overflow the box.
        Color.clear
            .overlay {
                if let resolved {
                    TimelineView(.animation) { context in
                        fitToHeight(resolved.clip.frames[frameIndex(resolved, at: context.date)])
                    }
                } else {
                    fitToHeight(fallback)
                }
            }
            .onChange(of: mood) { _, _ in start = Date() }
    }

    private func fitToHeight(_ image: UIImage) -> some View {
        GeometryReader { box in
            let aspect = image.size.width / max(image.size.height, 1)
            Image(uiImage: image)
                .resizable()
                .frame(width: box.size.height * aspect, height: box.size.height)
                .position(x: box.size.width / 2, y: box.size.height / 2)
        }
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
