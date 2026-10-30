import AppKit

/// Пыльное облачко из-под лап при жёстком приземлении: пиксельные клубы разлетаются в стороны и тают.
/// Его же другим цветом и в одну сторону — комья земли, когда закапывает, и облачко, когда пукнул.
@MainActor
final class Dust {
    private let panel = Pet.overlay()
    private let view = DustView()
    private var timer: Timer?
    private var start = Date()

    init() {
        panel.ignoresMouseEvents = true
        panel.contentView = view
    }

    /// feet — точка между лапами, pixel — размер пикселя спрайта, strength 0…1 — насколько сильно шлёпнулся.
    /// side — разлёт только в одну сторону (+1 вправо, −1 влево), иначе в обе.
    func puff(at feet: NSPoint, pixel: CGFloat, strength: CGFloat, below pet: NSWindow,
              color: NSColor? = nil, side oneSide: CGFloat? = nil) {
        let s = min(max(strength, 0), 1)
        view.pixel = pixel
        view.color = color ?? DustView.dust
        view.clouds = (0..<(4 + Int(s * 4))).map { i in
            let side: CGFloat = oneSide ?? (i % 2 == 0 ? 1 : -1)
            let radius = CGFloat.random(in: 1.4...2.4) * (0.8 + s * 0.5)
            return DustView.Cloud(
                x: side * .random(in: 3...7), y: radius,
                vx: side * .random(in: 16...36) * (0.7 + s * 0.6), vy: .random(in: 2...8),
                radius: radius, life: .random(in: 0.35...0.55))
        }
        view.time = 0
        let size = NSSize(width: pixel * 64, height: pixel * 20)
        panel.setFrame(NSRect(x: feet.x - size.width / 2, y: feet.y - pixel, width: size.width, height: size.height), display: false)
        view.frame = NSRect(origin: .zero, size: size)
        view.needsDisplay = true
        panel.order(.below, relativeTo: pet.windowNumber)  // клубы за питомцем, лапы не закрывают

        start = Date()
        timer?.invalidate()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func tick() {
        view.time = Date().timeIntervalSince(start)
        view.needsDisplay = true
        if view.time > (view.clouds.map(\.life).max() ?? 0) {
            timer?.invalidate()
            timer = nil
            panel.orderOut(nil)
        }
    }
}

/// Рисует клубы кругами из пикселей спрайта: общая обводка сначала, заливка поверх — соседние клубы сливаются.
final class DustView: NSView {
    struct Cloud {
        /// Всё в пикселях спрайта от точки между лапами.
        var x, y, vx, vy, radius: CGFloat
        var life: TimeInterval
    }

    static let dust = NSColor(srgbRed: 240 / 255, green: 230 / 255, blue: 214 / 255, alpha: 1)
    static let fart = NSColor(srgbRed: 196 / 255, green: 222 / 255, blue: 120 / 255, alpha: 1)
    static let dirt = NSColor(srgbRed: 150 / 255, green: 108 / 255, blue: 70 / 255, alpha: 1)

    var color = DustView.dust

    var clouds: [Cloud] = []
    var time: TimeInterval = 0
    var pixel: CGFloat = 3

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        let alive = clouds.compactMap { c -> (CGFloat, CGFloat, CGFloat, CGFloat)? in
            let p = CGFloat(time / c.life)
            guard p < 1 else { return nil }
            let t = CGFloat(time) * (1 - p * 0.5)  // разлёт тормозит
            return (c.x + c.vx * t, c.y + c.vy * t, c.radius * (1 - p * 0.6), 1 - p * p)
        }
        for (cx, cy, r, alpha) in alive {
            disc(cx, cy, r + 1, SpeechBubble.ink.withAlphaComponent(alpha * 0.55))
        }
        for (cx, cy, r, alpha) in alive {
            disc(cx, cy, r, color.withAlphaComponent(alpha))
        }
    }

    private func disc(_ cx: CGFloat, _ cy: CGFloat, _ r: CGFloat, _ color: NSColor) {
        color.setFill()
        let midX = (bounds.width / pixel / 2).rounded()
        for j in Int((cy - r).rounded(.down))...Int((cy + r).rounded(.up)) {
            for i in Int((cx - r).rounded(.down))...Int((cx + r).rounded(.up)) {
                let dx = CGFloat(i) + 0.5 - cx, dy = CGFloat(j) + 0.5 - cy
                guard dx * dx + dy * dy <= r * r, j >= -1 else { continue }
                NSRect(x: (midX + CGFloat(i)) * pixel, y: CGFloat(j + 1) * pixel, width: pixel, height: pixel).fill()
            }
        }
    }
}
