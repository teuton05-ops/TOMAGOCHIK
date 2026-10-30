import AppKit

/// Меняет только цвета шерсти. Глаза, нос, белые лапы, ошейник и прозрачность сохраняются.
enum PetCoat: String, CaseIterable, Identifiable {
    case original, cream, silver, cocoa
    var id: String { rawValue }
    var title: String {
        switch self {
        case .original: return "Родной"
        case .cream: return "Кремовый"
        case .silver: return "Серебристый"
        case .cocoa: return "Шоколадный"
        }
    }
    private var rgb: (Double, Double, Double) {
        switch self {
        case .original: return (240, 160, 75)
        case .cream: return (244, 217, 166)
        case .silver: return (169, 182, 194)
        case .cocoa: return (148, 100, 76)
        }
    }
    var swatch: NSColor {
        let (r, g, b) = rgb
        return NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
    }

    // Палитра и ступени освещения совпадают с art/pixel.py, cat.py и dog.py.
    // Точное совпадение цвета не позволяет перекрасить похожие по тону глаза и жетон.
    private static let furColors: Set<UInt32> = {
        let bases = [(240,160,75), (204,126,56), (196,112,44),
                     (226,178,118), (190,142,88), (139,92,58)]
        var colors = Set<UInt32>()
        for (r,g,b) in bases {
            colors.insert(key(r,g,b))
            for light in [1.10, 1.04, 1.0, 0.96, 0.90, 1.18, 0.81] {
                for texture in [1.0, 1.06, 0.94] {
                    let k = light * texture
                    // Python round использует округление к чётному.
                    colors.insert(key(min(255, Int((Double(r)*k).rounded(.toNearestOrEven))),
                                      min(255, Int((Double(g)*k).rounded(.toNearestOrEven))),
                                      min(255, Int((Double(b)*k).rounded(.toNearestOrEven)))))
                }
            }
        }
        for (r,g,b) in [(167,116,73), (113,73,48), (170,96,42), (163,112,69)] {
            colors.insert(key(r,g,b))
        }
        return colors
    }()

    private static func key(_ r: Int, _ g: Int, _ b: Int) -> UInt32 {
        UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b)
    }

    func render(_ image: CGImage) -> CGImage {
        guard self != .original,
              let context = CGContext(data: nil, width: image.width, height: image.height,
                                      bitsPerComponent: 8, bytesPerRow: image.width * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
              let data = context.data else { return image }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        let pixels = data.bindMemory(to: UInt8.self, capacity: image.width * image.height * 4)
        let (red, green, blue) = rgb
        for offset in stride(from: 0, to: image.width * image.height * 4, by: 4) {
            let r = Int(pixels[offset]), g = Int(pixels[offset+1]), b = Int(pixels[offset+2])
            guard pixels[offset+3] == 255, Self.furColors.contains(Self.key(r,g,b)) else { continue }
            let light = (0.299 * Double(r) + 0.587 * Double(g) + 0.114 * Double(b)) / 180
            for (channel, value) in [red, green, blue].enumerated() {
                pixels[offset + channel] = UInt8(min(255, max(0, (value * light).rounded())))
            }
        }
        return context.makeImage() ?? image
    }
}
