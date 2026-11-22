import SwiftUI

struct MascotStage: View {
    let mascot: Pet
    /// True when the user practised yesterday or today.
    var active = true
    var fullBleed = false
    @Environment(\.mascotPalette) private var palette
    /// Active: opening the page waves, a tap waves, tapping again while it waves dances; each then returns
    /// to the looping idle. Inactive: the looping sad clip, and taps do nothing. Only plays saved clips.
    @State private var burst: PetMood?
    @State private var burstToken = 0

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
            .clipShape(RoundedRectangle(cornerRadius: fullBleed ? 0 : 16))
            .animation(.easeInOut(duration: 0.4), value: library.activeID)
        }
    }

    private var playing: some View {
        var shown = mascot
        shown.mood = active ? (burst ?? .idle) : .cry
        return shown
            .onAppear { if active { play(.wave) } }
            .onChange(of: active) { _, nowActive in if nowActive { play(.wave) } else { burst = nil } }
            .onTapGesture { tapped() }
    }

    private func tapped() {
        guard active else { return }
        switch burst {
        case nil: play(.wave)
        case .wave?: play(.dance)
        default: break
        }
    }

    private func play(_ mood: PetMood) {
        let library = AvatarLibrary.shared
        guard let id = library.activeID, let clip = library.clip(id: id, mood: mood) else { return }
        burst = mood
        burstToken += 1
        let token = burstToken
        Task {
            try? await Task.sleep(for: .seconds(clip.duration))
            if burstToken == token { burst = nil }
        }
    }
}
