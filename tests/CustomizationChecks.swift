import AppKit
import ImageIO

@main
struct CustomizationChecks {
    static func main() {
        let suite = "Tamagochi.CustomizationChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        precondition(PetPreferences.load(defaults) == .standard)

        // Миграция прежнего размера и независимые окрасы переживают сохранение.
        defaults.set(3, forKey: "scale")
        precondition(PetPreferences.load(defaults).scale == 2)
        defaults.set(4, forKey: "scale")
        precondition(PetPreferences.load(defaults).scale == 2.5)
        var custom = PetPreferences.standard
        custom.selection = "duo"
        custom.scale = 3.1
        custom.catCoat = .silver
        custom.dogCoat = .cocoa
        custom.opacity = 0.65
        custom.speed = 1.75
        custom.sleepMinutes = 0
        custom.chasesCursor = false
        custom.chatFrequency = 0.5
        custom.reminderSound = false
        custom.cornerMode = true
        custom.cornerSide = "left"
        custom.save(defaults)
        precondition(PetPreferences.load(defaults) == custom)

        // Некорректные сохранённые числа не попадают в физику и прозрачность.
        defaults.set(Double.infinity, forKey: "scale48")
        defaults.set(-5.0, forKey: "petOpacity")
        defaults.set(999.0, forKey: "movementSpeed")
        defaults.set(-1.0, forKey: "sleepMinutes")
        defaults.set("invalid", forKey: "cornerSide")
        let repaired = PetPreferences.load(defaults)
        precondition(repaired.scale == 2 && repaired.opacity == 0.35 && repaired.speed == 2 && repaired.sleepMinutes == 5)
        precondition(repaired.cornerSide == "right")
        defaults.set(["test reminder"], forKey: "reminders")
        defaults.set(["test file"], forKey: "held")
        PetPreferences.standard.save(defaults)
        precondition(PetPreferences.load(defaults) == .standard)
        precondition(defaults.stringArray(forKey: "reminders") == ["test reminder"])
        precondition(defaults.stringArray(forKey: "held") == ["test file"])

        // Внешний монитор может иметь отрицательные координаты; крупный питомец
        // и второй друг должны оставаться внутри рабочей области.
        for area in [CGRect(x: 0, y: 30, width: 1440, height: 850),
                     CGRect(x: -1920, y: -200, width: 1920, height: 1080)] {
            for size: CGFloat in [48, 96, 192] {
                for left in [false, true] {
                    let first = CornerSeat.origin(in: area, size: size, order: 0, left: left)
                    let second = CornerSeat.origin(in: area, size: size, order: 1, left: left)
                    precondition(first.y == area.minY && second.y == area.minY)
                    precondition(first.x >= area.minX && first.x + size <= area.maxX)
                    precondition(second.x >= area.minX && second.x + size <= area.maxX)
                    precondition(left ? second.x > first.x : second.x < first.x)
                }
            }
        }

        // Искусственные образцы проверяют защиту глаз, носа, ошейника и жетона.
        let samples: [[UInt8]] = [[240,160,75,255], [226,178,118,255], [43,29,26,255],
                                  [242,139,154,255], [255,244,230,255], [250,204,82,255],
                                  [158,100,52,255], [214,64,69,255], [0,0,0,0]]
        let context = CGContext(data: nil, width: samples.count, height: 1, bitsPerComponent: 8,
                                bytesPerRow: samples.count*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        let pixels = context.data!.bindMemory(to: UInt8.self, capacity: samples.count*4)
        for (index, color) in samples.enumerated() {
            for channel in 0..<4 { pixels[index*4+channel] = color[channel] }
        }
        let original = context.makeImage()!
        for coat in PetCoat.allCases where coat != .original {
            let painted = rgba(coat.render(original))
            for index in 2..<samples.count {
                precondition(Array(painted[(index*4)..<(index*4+4)]) == samples[index], "Protected color changed: \(coat), \(index)")
            }
            precondition(Array(painted[0..<3]) != Array(samples[0][0..<3]))
        }

        var sheets = 0
        for url in try! FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "sprites"), includingPropertiesForKeys: nil)
            where url.pathExtension == "png" {
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)!
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)!
            let baseline = rgba(image)
            for coat in PetCoat.allCases {
                let painted = coat.render(image)
                precondition(painted.width == image.width && painted.height == image.height)
                let data = rgba(painted)
                for index in stride(from: 3, to: data.count, by: 4) {
                    precondition(data[index] == baseline[index], "Alpha changed in \(url.lastPathComponent)")
                }
                if coat == .original { precondition(data == baseline) }
                else { precondition(data != baseline, "Coat did not change in \(url.lastPathComponent)") }
            }
            sheets += 1
        }
        precondition(sheets == 32)
        print("PASS: migration, persistence, invalid values, reset isolation, protected colors, and all 32 sheets × 4 coats.")
    }

    private static func rgba(_ image: CGImage) -> [UInt8] {
        let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8,
                                bytesPerRow: image.width*4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue)!
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return Array(UnsafeBufferPointer(start: context.data!.assumingMemoryBound(to: UInt8.self), count: image.width*image.height*4))
    }
}
