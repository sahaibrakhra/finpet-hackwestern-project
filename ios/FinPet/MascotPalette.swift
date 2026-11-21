import SwiftUI

struct MascotPalette {
    let paper: Color
    let panel: Color
    let stage: Color
    let ground: Color
    let rule: Color
    let accent: Color

    init(base: UIColor) {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        if !base.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            red = 0.55
            green = 0.77
            blue = 0.59
        }
        func mix(_ amount: Double, into neutral: Double) -> Color {
            Color(red: neutral * (1 - amount) + red * amount,
                  green: neutral * (1 - amount) + green * amount,
                  blue: neutral * (1 - amount) + blue * amount)
        }
        paper = mix(0.085, into: 0.995)
        panel = mix(0.17, into: 0.99)
        stage = mix(0.27, into: 0.99)
        ground = mix(0.42, into: 0.975)
        rule = mix(0.26, into: 0.96)
        accent = mix(0.38, into: 0.10)
    }

    static func baseColour(photo: Data) -> UIColor? {
        guard let image = UIImage(data: photo)?.cgImage,
              let bitmap = CGContext(data: nil, width: 48, height: 48, bitsPerComponent: 8,
                                     bytesPerRow: 192, space: CGColorSpaceCreateDeviceRGB(),
                                     bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let buffer = bitmap.data else { return nil }

        bitmap.draw(image, in: CGRect(x: 0, y: 0, width: 48, height: 48))
        let bytes = buffer.assumingMemoryBound(to: UInt8.self)
        var groups: [Int: (r: Double, g: Double, b: Double, count: Double)] = [:]
        for y in 4..<44 {
            for x in 10..<38 {
                let index = (y * 48 + x) * 4
                guard bytes[index + 3] > 235 else { continue }
                let r = Double(bytes[index]) / 255
                let g = Double(bytes[index + 1]) / 255
                let b = Double(bytes[index + 2]) / 255
                let high = max(r, g, b)
                let low = min(r, g, b)
                guard high - low > 0.09, high > 0.2, low < 0.87 else { continue }
                let key = Int(r * 5) * 36 + Int(g * 5) * 6 + Int(b * 5)
                let weight = 1.0 + (1.0 - Double(abs(x - 24)) / 24)
                var group = groups[key] ?? (0, 0, 0, 0)
                group.r += r * weight
                group.g += g * weight
                group.b += b * weight
                group.count += weight
                groups[key] = group
            }
        }
        guard let dominant = groups.sorted(by: {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }).first?.value else { return nil }
        return UIColor(red: dominant.r / dominant.count, green: dominant.g / dominant.count,
                       blue: dominant.b / dominant.count, alpha: 1)
    }
}

private struct MascotPaletteKey: EnvironmentKey {
    static var defaultValue: MascotPalette { MascotPalette(base: UIColor(PetColor.leaf.fill)) }
}

extension EnvironmentValues {
    var mascotPalette: MascotPalette {
        get { self[MascotPaletteKey.self] }
        set { self[MascotPaletteKey.self] = newValue }
    }
}
