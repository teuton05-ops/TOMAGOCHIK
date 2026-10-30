import AppKit

/// Тень под лапами: пиксельный овал на поверхности. Чем выше питомец над ней, тем она меньше и бледнее.
@MainActor
final class Shadow {
    private let panel = Pet.overlay()
    private let view = ShadowView()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// surface — высота поверхности под питомцем, nil — тени нет (лезет по стене).
    func update(x: CGFloat, feet: CGFloat, surface: CGFloat?, pixel: CGFloat, below pet: NSWindow) {
        guard let surface else {
            panel.orderOut(nil)
            return
        }
        let k = max(0.35, 1 - (feet - surface) / (pixel * 32 * 5))
        let frame = NSRect(x: (x - pixel * 12).rounded(), y: (surface - pixel * 2).rounded(), width: pixel * 24, height: pixel * 4)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        view.frame = NSRect(origin: .zero, size: frame.size)
        if view.k != k || view.pixel != pixel {
            view.k = k
            view.pixel = pixel
            view.needsDisplay = true
        }
        if !panel.isVisible { panel.order(.below, relativeTo: pet.windowNumber) }
    }
}

private final class ShadowView: NSView {
    var k: CGFloat = 1
    var pixel: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        NSColor.black.withAlphaComponent(0.22 * k).setFill()
        let half = (9 * k).rounded()
        // Три ряда пикселей: середина шире, края уже — овал
        for (row, inset) in [(1, 0.0), (2, 0.0), (0, 2.0), (3, 2.0)] {
            let w = max(0, half - inset)
            guard w > 0 else { continue }
            NSRect(x: (12 - w) * pixel, y: CGFloat(row) * pixel, width: w * 2 * pixel, height: pixel).fill()
        }
    }
}

/// Погода вокруг питомца: в дождь — зонтик над головой и капли вокруг, в снег — падающие снежинки.
@MainActor
final class WeatherFX {
    private let panel = Pet.overlay()
    private let view = WeatherView()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }

    /// feet — точка между лапами, head — голова; kind nil — ничего не показывать.
    func update(feet: NSPoint, head: NSPoint, kind: Weather.Kind?, pixel: CGFloat, above pet: NSWindow) {
        guard let kind, kind == .rain || kind == .snow else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let size = NSSize(width: pixel * 64, height: pixel * 56)
        let frame = NSRect(x: (feet.x - size.width / 2).rounded(), y: feet.y.rounded(), width: size.width, height: size.height)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        view.frame = NSRect(origin: .zero, size: size)
        view.kind = kind
        view.pixel = pixel
        view.headX = (head.x - frame.minX) / pixel
        view.now = Date().timeIntervalSinceReferenceDate
        view.needsDisplay = true
        if !panel.isVisible { panel.order(.above, relativeTo: pet.windowNumber) }
    }

    func hide() {
        panel.orderOut(nil)
    }
}

private final class WeatherView: NSView {
    var kind = Weather.Kind.rain
    var pixel: CGFloat = 3
    var headX: CGFloat = 32
    var now: TimeInterval = 0

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        let w = bounds.width / pixel, h = bounds.height / pixel
        // Купол зонтика: над головой, нижний край на высоте 34 пикселей спрайта, ручка спускается к макушке
        let canopy = (x0: headX - 8, x1: headX + 8, y: CGFloat(34))
        let rain = kind == .rain
        let count = rain ? 26 : 18
        for i in 0..<count {
            let seed = Double(i) * 12.9898
            let x = (CGFloat(abs(sin(seed) * 43758.5453).truncatingRemainder(dividingBy: 1)) * w).rounded()
            let speed = rain ? 70.0 : 9.0
            let phase = abs(cos(seed) * 9631.17).truncatingRemainder(dividingBy: 1)
            var y = h - CGFloat((now * speed / Double(h) + phase).truncatingRemainder(dividingBy: 1)) * h
            if !rain { y = y.rounded() }
            let sway = rain ? 0 : (sin(now * 1.5 + seed) * 2).rounded()
            // Под зонтиком сухо
            if rain && x >= canopy.x0 && x <= canopy.x1 && y < canopy.y { continue }
            if rain {
                NSColor(srgbRed: 120 / 255, green: 160 / 255, blue: 230 / 255, alpha: 0.8).setFill()
                NSRect(x: x * pixel, y: y.rounded() * pixel, width: pixel, height: pixel * 2).fill()
            } else {
                SpeechBubble.ink.withAlphaComponent(0.35).setFill()
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    NSRect(x: (x + sway + CGFloat(dx)) * pixel, y: (y + CGFloat(dy)) * pixel, width: pixel, height: pixel).fill()
                }
                NSColor.white.setFill()
                NSRect(x: (x + sway) * pixel, y: y * pixel, width: pixel, height: pixel).fill()
            }
        }
        if rain {
            let art = Arts.umbrella
            let center = NSPoint(x: headX * pixel, y: (canopy.y + CGFloat(art.height) / 2 - 6) * pixel)
            art.draw(in: NSRect(x: center.x - 50, y: center.y - 50, width: 100, height: 100), pixel: pixel)
        }
    }
}

/// Значки над головой: «!» — испугался, «?» — не понял, сердечки — гладят, нотки — танцует. Всплывают и тают.
@MainActor
final class Emotes {
    enum Kind { case startle, puzzled, heart, note }

    private let panel = Pet.overlay()
    private let view = EmotesView()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }

    func show(_ kind: Kind) {
        let floats = kind == .heart || kind == .note
        let drift: CGFloat = floats ? .random(in: -5...5) : 0
        view.items.append(EmotesView.Item(kind: kind, start: Date(), x: drift, life: floats ? 1.1 : 1.3))
    }

    func hide() {
        view.items = []
        panel.orderOut(nil)
    }

    /// Каждый кадр питомца: держим панель над головой и перерисовываем.
    func update(head: NSPoint, pixel: CGFloat) {
        let now = Date()
        view.items.removeAll { now.timeIntervalSince($0.start) > $0.life }
        guard !view.items.isEmpty else {
            if panel.isVisible { panel.orderOut(nil) }
            return
        }
        let size = NSSize(width: pixel * 24, height: pixel * 24)
        panel.setFrame(NSRect(x: (head.x - size.width / 2).rounded(), y: head.y.rounded(), width: size.width, height: size.height), display: false)
        view.frame = NSRect(origin: .zero, size: size)
        view.pixel = pixel
        view.now = now
        view.needsDisplay = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }
}

private final class EmotesView: NSView {
    struct Item {
        let kind: Emotes.Kind
        let start: Date
        let x: CGFloat
        let life: TimeInterval
    }

    var items: [Item] = []
    var pixel: CGFloat = 3
    var now = Date()

    // Рисунки сверху вниз: X — заливка; обводка строится вокруг.
    private static let shapes: [Emotes.Kind: (rows: [String], color: NSColor)] = [
        .startle: (["XX", "XX", "XX", "XX", "..", "XX"], NSColor(srgbRed: 1, green: 214 / 255, blue: 90 / 255, alpha: 1)),
        .puzzled: (["XXX.", "...X", "..X.", ".X..", "....", ".X.."], .white),
        .heart: ([".X.X.", "XXXXX", "XXXXX", ".XXX.", "..X.."], NSColor(srgbRed: 233 / 255, green: 84 / 255, blue: 107 / 255, alpha: 1)),
        .note: (["..XX", "..X.", "..X.", "XXX.", "XX.."], NSColor(srgbRed: 150 / 255, green: 120 / 255, blue: 1, alpha: 1)),
    ]

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        for item in items {
            guard let shape = Self.shapes[item.kind] else { continue }
            let t = CGFloat(now.timeIntervalSince(item.start) / item.life)
            // Значок выпрыгивает, потом медленно поднимается; сердечки плывут вверх и в сторону
            let rise = item.kind == .heart || item.kind == .note ? t * 14 : min(t * 8, 2) + t * 2
            let alpha = t < 0.7 ? 1 : max(0, 1 - (t - 0.7) / 0.3)
            let w = shape.rows[0].count, h = shape.rows.count
            let ox = (12 + item.x * t - CGFloat(w) / 2).rounded(), oy = (2 + rise).rounded()
            var fill = Set<[Int]>()
            for (r, row) in shape.rows.enumerated() {
                for (c, ch) in row.enumerated() where ch == "X" { fill.insert([c, h - 1 - r]) }
            }
            SpeechBubble.ink.withAlphaComponent(alpha).setFill()
            for p in fill {
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where !fill.contains([p[0] + dx, p[1] + dy]) {
                    pixelRect(ox + CGFloat(p[0] + dx), oy + CGFloat(p[1] + dy)).fill()
                }
            }
            shape.color.withAlphaComponent(alpha).setFill()
            for p in fill { pixelRect(ox + CGFloat(p[0]), oy + CGFloat(p[1])).fill() }
        }
    }

    private func pixelRect(_ x: CGFloat, _ y: CGFloat) -> NSRect {
        NSRect(x: x * pixel, y: y * pixel, width: pixel, height: pixel)
    }
}
