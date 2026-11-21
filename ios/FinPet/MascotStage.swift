import SwiftUI

struct MascotStage: View {
    let mascot: Pet
    @Environment(\.mascotPalette) private var palette
    /// Tap = wave, long press = dance, then back to idle. Only plays clips that are already saved.
    @State private var burst: PetMood?

    var body: some View {
        let library = AvatarLibrary.shared
        GeometryReader { stage in
            let height = stage.size.height
            let mascotSize = min(stage.size.width * 0.96, height * 0.94)
            ZStack(alignment: .bottom) {
                palette.stage
                Rectangle()
                    .fill(palette.ground)
                    .frame(height: height * 0.23)
                    .accessibilityHidden(true)
                Ellipse()
                    .fill(palette.accent.opacity(0.12))
                    .frame(width: mascotSize * 0.53, height: height * 0.055)
                    .padding(.bottom, height * 0.11)
                    .accessibilityHidden(true)

                playing
                    .frame(width: mascotSize, height: mascotSize)
                    .padding(.bottom, height * 0.035)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .animation(.easeInOut(duration: 0.4), value: library.activeID)
        }
    }

    private var playing: some View {
        var shown = mascot
        if let burst { shown.mood = burst }
        return shown
            .onTapGesture { play(.wave) }
            .onLongPressGesture { play(.dance) }
    }

    private func play(_ mood: PetMood) {
        let library = AvatarLibrary.shared
        guard burst == nil, let id = library.activeID,
              let clip = library.clip(id: id, mood: mood) else { return }
        burst = mood
        Task {
            try? await Task.sleep(for: .seconds(clip.duration))
            burst = nil
        }
    }
}
