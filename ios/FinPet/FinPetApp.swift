import SwiftUI
import PhotosUI

let ink = Color(red: 0.09, green: 0.18, blue: 0.15)
let forest = Color(red: 0.13, green: 0.39, blue: 0.29)
let cream = Color(red: 0.975, green: 0.968, blue: 0.94)
let mint = Color(red: 0.88, green: 0.93, blue: 0.87)
let line = Color(red: 0.83, green: 0.88, blue: 0.84)
let muted = Color(red: 0.32, green: 0.40, blue: 0.36)
let honey = Color(red: 0.99, green: 0.93, blue: 0.80)

extension View {
    func petCard(_ color: Color = .white, radius: CGFloat = 22) -> some View {
        self.padding(16).background(color, in: RoundedRectangle(cornerRadius: radius))
            .overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(line) }
    }
}

struct ActionButton: View {
    @Environment(\.mascotPalette) private var palette
    let title: String
    var secondary = false
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title).font(.headline).frame(maxWidth: .infinity).padding(.vertical, 14)
                .foregroundStyle(secondary ? palette.accent : .white)
                .background(secondary ? palette.panel : palette.accent, in: RoundedRectangle(cornerRadius: 15))
                .overlay { RoundedRectangle(cornerRadius: 15).strokeBorder(secondary ? palette.rule : .clear) }
        }
        .buttonStyle(.plain)
    }
}

struct Meter: View {
    @Environment(\.mascotPalette) private var palette
    let progress: Double
    var background = Color.white
    var body: some View {
        GeometryReader { proxy in
            Capsule().fill(background)
                .overlay(alignment: .leading) {
                    Capsule().fill(palette.accent).frame(width: proxy.size.width * min(1, max(0, progress)))
                }
        }
        .frame(height: 7)
        .accessibilityLabel("Progress")
        .accessibilityValue(progress.formatted(.percent.precision(.fractionLength(0))))
    }
}

enum PetColor: String, CaseIterable {
    case leaf = "Leaf", sky = "Sky", berry = "Berry", sunny = "Sunny"
    var fill: Color {
        switch self {
        case .leaf: Color(red: 0.55, green: 0.77, blue: 0.59)
        case .sky: Color(red: 0.59, green: 0.76, blue: 0.89)
        case .berry: Color(red: 0.95, green: 0.65, blue: 0.73)
        case .sunny: Color(red: 0.98, green: 0.81, blue: 0.40)
        }
    }
}

// Shared avatar for Home, lessons, customization, and Friends.
struct Pet: View {
    let color: PetColor
    var photo: Data?
    var mood: PetMood = .idle

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            if let photo, let image = UIImage(data: photo) {
                // Generated full-body avatar (transparent background): animated when clips are saved, never cropped.
                AnimatedAvatar(mood: mood, fallback: image)
            } else {
                // Replace the still renderer here when the animated avatar is ready.
                Canvas { ctx, size in
                    var ctx = ctx
                    ctx.scaleBy(x: size.width / 120, y: size.height / 120)
                    func oval(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ fill: Color, border: Bool = true) {
                        let path = Path(ellipseIn: CGRect(x: x, y: y, width: w, height: h))
                        ctx.fill(path, with: .color(fill))
                        if border { ctx.stroke(path, with: .color(ink), lineWidth: 3) }
                    }
                    func shape(_ fill: Color? = nil, _ draw: (inout Path) -> Void) {
                        var path = Path()
                        draw(&path)
                        if let fill { ctx.fill(path, with: .color(fill)) }
                        ctx.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                    }
                    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
                    oval(12, 103, 96, 14, forest.opacity(0.13), border: false)
                    oval(17, 66, 89, 24, color.fill)
                    oval(22, 37, 79, 66, color.fill)
                    shape { path in path.move(to: p(60, 39)); path.addQuadCurve(to: p(64, 17), control: p(59, 24)) }
                    shape(PetColor.leaf.fill) { path in
                        path.move(to: p(63, 20)); path.addQuadCurve(to: p(87, 13), control: p(77, 4))
                        path.addQuadCurve(to: p(63, 20), control: p(77, 26)); path.closeSubpath()
                    }
                    shape(PetColor.leaf.fill) { path in
                        path.move(to: p(61, 23)); path.addQuadCurve(to: p(40, 36), control: p(49, 24))
                        path.addQuadCurve(to: p(61, 23), control: p(35, 15)); path.closeSubpath()
                    }
                    for x in [CGFloat(46), 72] {
                        oval(x, 63, 8, 11, ink, border: false)
                        oval(x + 2, 64, 2, 3, .white, border: false)
                        shape { path in path.move(to: p(x - 2, 57)); path.addQuadCurve(to: p(x + 10, 57), control: p(x + 4, 53)) }
                    }
                    oval(34, 76, 10, 5, .pink.opacity(0.55), border: false)
                    oval(80, 76, 10, 5, .pink.opacity(0.55), border: false)
                    shape { path in path.move(to: p(55, 78)); path.addQuadCurve(to: p(67, 78), control: p(61, 84)) }
                    oval(27, 94, 33, 16, color.fill)
                    oval(62, 94, 33, 16, color.fill)
                }
            }

        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel("Mascot")
    }
}

@main
struct FinPetApp: App {
    @StateObject private var auth = AuthSession()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                switch auth.state {
                case .checking: cream.ignoresSafeArea()
                case .signedOut: LoginView()
                case .signedIn: FinPetRoot()
                }
            }
            .environmentObject(auth)
            .onChange(of: scenePhase, initial: true) { _, phase in
                if phase == .active { auth.restore() }
            }
            .preferredColorScheme(.light)
        }
    }
}
