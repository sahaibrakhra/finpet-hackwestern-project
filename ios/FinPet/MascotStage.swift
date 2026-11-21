import SwiftUI

struct MascotStage: View {
    let mascot: Pet
    /// Tap = wave, long press = dance, then back to idle. Only plays clips that are already saved.
    @State private var burst: PetMood?

    var body: some View {
        let library = AvatarLibrary.shared
        GeometryReader { stage in
            let height = stage.size.height
            let mascotSize = min(stage.size.width * 0.96, height * 0.94)
            ZStack(alignment: .bottom) {
                // The stage takes the color of the active avatar's background.
                RoundedRectangle(cornerRadius: 25).fill(library.activeBackground ?? mint)
                Circle()
                    .fill(.white.opacity(0.32))
                    .frame(width: height * 0.66)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(.top, -height * 0.13)
                    .padding(.trailing, -height * 0.12)
                    .accessibilityHidden(true)

                UnevenRoundedRectangle(topLeadingRadius: 32, bottomLeadingRadius: 25,
                                       bottomTrailingRadius: 25, topTrailingRadius: 32)
                    .fill(forest.opacity(0.10))
                    .frame(height: height * 0.24)
                    .accessibilityHidden(true)

                playing
                    .frame(width: mascotSize, height: mascotSize)
                    .padding(.bottom, height * 0.035)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 25))
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
