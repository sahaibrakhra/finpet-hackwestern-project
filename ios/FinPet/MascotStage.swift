import SwiftUI

struct MascotStage: View {
    let mascot: Pet

    var body: some View {
        GeometryReader { stage in
            let height = stage.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 25).fill(mint)
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

                mascot
                    .frame(width: min(stage.size.width * 0.78, height * 0.81),
                           height: height * 0.81)
                    .padding(.bottom, height * 0.08)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 25))
        }
    }
}
