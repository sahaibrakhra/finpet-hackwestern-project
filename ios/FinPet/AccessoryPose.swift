import SwiftUI

/// Coordinates are normalized to the saved image, including its transparent margins.
struct AccessoryPose {
    var x: CGFloat
    var crown: CGFloat
    var neck: CGFloat
    var angle: Double
    var headWidth: CGFloat

    static let portrait = Self(x: 0.5, crown: 0.15, neck: 0.38, angle: 0, headWidth: 0.46)

    init(x: CGFloat, crown: CGFloat, neck: CGFloat, angle: Double, headWidth: CGFloat) {
        self.x = x
        self.crown = crown
        self.neck = neck
        self.angle = angle
        self.headWidth = headWidth
    }

    init(image: UIImage) {
        self = .portrait
        guard let source = image.cgImage else { return }
        let width = 48
        let height = 64
        let bytesPerRow = width * 4
        guard let bitmap = CGContext(data: nil, width: width, height: height,
                                     bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                                     space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = bitmap.data else { return }

        bitmap.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
        let pixels = buffer.assumingMemoryBound(to: UInt8.self)
        let rows = (0..<height).map { y in
            (0..<width).filter { x in pixels[y * bytesPerRow + x * 4 + 3] > 100 }
        }
        let occupied = rows.indices.filter { rows[$0].count >= 3 }
        guard let top = occupied.first, let bottom = occupied.last, bottom - top >= 12,
              rows.filter({ $0.count >= width - 2 }).count < height / 2 else { return }

        let length = Double(bottom - top)
        func center(from start: Double, to end: Double) -> Double? {
            let lower = top + Int(length * start)
            let upper = top + Int(length * end)
            let centers = (lower...upper).compactMap { row -> Double? in
                guard let left = rows[row].first, let right = rows[row].last else { return nil }
                return Double(left + right) / 2
            }.sorted()
            return centers.isEmpty ? nil : centers[centers.count / 2]
        }
        guard let upper = center(from: 0.04, to: 0.16),
              let lower = center(from: 0.19, to: 0.29) else { return }

        let headRows = (top + Int(length * 0.04))...(top + Int(length * 0.23))
        let spans = headRows.compactMap { row -> Int? in
            guard let left = rows[row].first, let right = rows[row].last else { return nil }
            return right - left + 1
        }.sorted()
        if !spans.isEmpty {
            headWidth = min(0.75, max(0.13, CGFloat(spans[spans.count * 2 / 3]) / CGFloat(width)))
        }
        x = upper / Double(width)
        crown = (Double(top) + length * 0.09) / Double(height)
        neck = (Double(top) + length * 0.32) / Double(height)
        let dx = (lower - upper) / Double(width) * Double(source.width) / Double(source.height)
        let dy = length * 0.19 / Double(height)
        angle = min(24, max(-24, -atan2(dx, dy) * 180 / .pi))
    }

    func smoothed(toward other: Self, weight: Double) -> Self {
        Self(x: x + (other.x - x) * weight,
             crown: crown + (other.crown - crown) * weight,
             neck: neck + (other.neck - neck) * weight,
             angle: angle + (other.angle - angle) * weight,
             headWidth: headWidth + (other.headWidth - headWidth) * weight)
    }
}

struct MascotAccessory: View {
    let name: String
    let pose: AccessoryPose
    let generated: Bool

    var body: some View {
        GeometryReader { bounds in
            let width = bounds.size.width
            let height = bounds.size.height
            if name == "Toque" {
                // Size against the detected head, with a height cap for the hat's long tassels.
                let aspect = CGFloat(257) / 480
                let hatWidth = min(width * pose.headWidth * 1.18, height * 0.65 * aspect)
                let hatHeight = hatWidth / aspect
                let brim = CGFloat(0.59)
                let centerY = max(hatHeight * 0.50, height * pose.crown - hatHeight * (brim - 0.50))
                Image("MascotToque").resizable().scaledToFit()
                    .frame(width: hatWidth, height: hatHeight)
                    .rotationEffect(.degrees(pose.angle), anchor: UnitPoint(x: 0.5, y: brim))
                    .position(x: width * pose.x, y: centerY)
            } else if name == "Scarf" {
                Image("MascotScarf").resizable().scaledToFit()
                    .frame(width: width * (generated ? 0.62 : 0.52), height: height * (generated ? 0.18 : 0.32))
                    .rotationEffect(.degrees(pose.angle * 0.55))
                    .position(x: width * pose.x, y: height * pose.neck)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
