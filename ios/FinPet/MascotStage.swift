import SwiftUI

struct MascotStage: View {
    var body: some View {
        // Mount the animated avatar here. Home owns the stage size.
        ZStack {
            RoundedRectangle(cornerRadius: 25).fill(mint)
            RoundedRectangle(cornerRadius: 25)
                .strokeBorder(forest.opacity(0.32), style: StrokeStyle(lineWidth: 1, dash: [6, 4]))
            VStack(spacing: 10) {
                Image(systemName: "leaf").font(.system(size: 34, weight: .medium))
                    .accessibilityHidden(true)
                Text("Mascot preview").font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(forest)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
