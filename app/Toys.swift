import AppKit

/// Маленькая пиксельная картинка из строк: символ — цвет из палитры, точка — пусто.
/// Обводка цветом чернил строится вокруг заливки сама.
struct PixelArt {
    let rows: [String]
    let palette: [Character: NSColor]

    var width: Int { rows.map(\.count).max() ?? 0 }
    var height: Int { rows.count }

    @MainActor
    func draw(in rect: NSRect, pixel: CGFloat, alpha: CGFloat = 1) {
        var fill: [[Int]: NSColor] = [:]
        for (r, row) in rows.enumerated() {
            for (c, ch) in row.enumerated() {
                if let color = palette[ch] { fill[[c, height - 1 - r]] = color }
            }
        }
        // Картинка с полем в пиксель под обводку, по центру rect
        let ox = rect.midX - CGFloat(width) * pixel / 2, oy = rect.midY - CGFloat(height) * pixel / 2
        func px(_ x: Int, _ y: Int) -> NSRect {
            NSRect(x: (ox + CGFloat(x) * pixel).rounded(), y: (oy + CGFloat(y) * pixel).rounded(), width: pixel, height: pixel)
        }
        SpeechBubble.ink.withAlphaComponent(alpha).setFill()
        for p in fill.keys {
            for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] where fill[[p[0] + dx, p[1] + dy]] == nil {
                px(p[0] + dx, p[1] + dy).fill()
            }
        }
        for (p, color) in fill {
            color.withAlphaComponent(alpha).setFill()
            px(p[0], p[1]).fill()
        }
    }
}

/// Пиксельная картинка поверх всех окон в заданной точке экрана.
@MainActor
final class Prop {
    let panel = Pet.overlay()
    let view = PropView()

    init(clickable: Bool = false) {
        panel.ignoresMouseEvents = !clickable
        panel.contentView = view
    }

    /// center — середина картинки на экране, pixel — размер пикселя.
    func show(_ art: PixelArt, center: NSPoint, pixel: CGFloat, alpha: CGFloat = 1) {
        let side = CGFloat(max(art.width, art.height) + 2) * pixel
        let frame = NSRect(x: (center.x - side / 2).rounded(), y: (center.y - side / 2).rounded(), width: side, height: side)
        if panel.frame != frame { panel.setFrame(frame, display: false) }
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.art = art
        view.pixel = pixel
        view.alpha = alpha
        view.needsDisplay = true
        if !panel.isVisible { panel.orderFrontRegardless() }
    }

    func hide() {
        panel.orderOut(nil)
    }

    var isVisible: Bool { panel.isVisible }
}

final class PropView: NSView {
    var art: PixelArt?
    var pixel: CGFloat = 3
    var alpha: CGFloat = 1
    var onMouseDown: (() -> Void)?
    var onMouseDragged: (() -> Void)?
    var onMouseUp: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        bounds.fill()
        art?.draw(in: bounds, pixel: pixel, alpha: alpha)
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onMouseDown?() }
    override func mouseDragged(with event: NSEvent) { onMouseDragged?() }
    override func mouseUp(with event: NSEvent) { onMouseUp?() }
}

@MainActor
enum Arts {
    static let ball = PixelArt(rows: [
        "..RRR..",
        ".RWRRR.",
        "RWWRRRR",
        "RRRRRRR",
        "YYYYYYY",
        ".RRRRR.",
        "..RRR..",
    ], palette: ["R": NSColor(srgbRed: 232 / 255, green: 76 / 255, blue: 76 / 255, alpha: 1), "W": .white,
                 "Y": NSColor(srgbRed: 1, green: 214 / 255, blue: 90 / 255, alpha: 1)])

    private static let wings: [Character: NSColor] = [
        "P": NSColor(srgbRed: 128 / 255, green: 150 / 255, blue: 1, alpha: 1),
        "Y": NSColor(srgbRed: 1, green: 220 / 255, blue: 110 / 255, alpha: 1),
        "B": SpeechBubble.ink,
    ]
    /// Бабочка: крылья раскрыты и сложены.
    static let butterfly = [
        PixelArt(rows: ["..B.B..", "PP.B.PP", "PYPBPYP", "PPPBPPP", ".PPBPP.", "..P.P.."], palette: wings),
        PixelArt(rows: ["..B.B..", "...B...", "..PBP..", "..PBP..", "..YBY..", "...B..."], palette: wings),
    ]

    /// Зонтик над головой в дождь: купол в полоску, ручка-крючок.
    static let umbrella = PixelArt(rows: [
        "......RLR......",
        "...RRLLLRRL....",
        "..RRLLLRRRLLR..",
        ".RRLLLRRRLLLRR.",
        "RRLLLRRRRLLLRRR",
        "R.L.R.R.R.L.R.R",
        ".......H.......",
        ".......H.......",
        ".......H.......",
        ".......H.......",
        ".....H.H.......",
        "......H........",
    ], palette: ["R": NSColor(srgbRed: 90 / 255, green: 140 / 255, blue: 230 / 255, alpha: 1),
                 "L": NSColor(srgbRed: 160 / 255, green: 196 / 255, blue: 1, alpha: 1),
                 "H": NSColor(srgbRed: 110 / 255, green: 72 / 255, blue: 44 / 255, alpha: 1)])

    /// Подушка под головой, когда дремлет ночью.
    static let pillow = PixelArt(rows: [".WWWWWWWW.", "WWBWWWWBWW", "WWWWWWWWWW", ".WWWWWWWW."],
                                 palette: ["W": NSColor(srgbRed: 236 / 255, green: 240 / 255, blue: 1, alpha: 1),
                                           "B": NSColor(srgbRed: 170 / 255, green: 186 / 255, blue: 240 / 255, alpha: 1)])

    /// Находки из корзины: картинка и как питомец её назовёт.
    static let trinkets: [(art: PixelArt, name: String)] = [
        (PixelArt(rows: ["G.G.G.G.", "GGGGGGGG", "G.G.G.GO"],
                  palette: ["G": NSColor(srgbRed: 230 / 255, green: 230 / 255, blue: 220 / 255, alpha: 1),
                            "O": NSColor(srgbRed: 60 / 255, green: 60 / 255, blue: 60 / 255, alpha: 1)]), "рыбью косточку"),
        (PixelArt(rows: ["..SS", "..SS", "..SS", "SSSS", "SSS."],
                  palette: ["S": NSColor(srgbRed: 240 / 255, green: 120 / 255, blue: 150 / 255, alpha: 1)]), "носок"),
        (PixelArt(rows: [".PPP.", "PWPPP", "PPPWP", ".PPP."],
                  palette: ["P": NSColor(srgbRed: 245 / 255, green: 245 / 255, blue: 240 / 255, alpha: 1),
                            "W": NSColor(srgbRed: 200 / 255, green: 200 / 255, blue: 195 / 255, alpha: 1)]), "скомканную бумажку"),
        (PixelArt(rows: [".G.", "AAA", ".Y.", "AAA"],
                  palette: ["G": NSColor(srgbRed: 110 / 255, green: 170 / 255, blue: 80 / 255, alpha: 1),
                            "A": NSColor(srgbRed: 230 / 255, green: 70 / 255, blue: 60 / 255, alpha: 1),
                            "Y": NSColor(srgbRed: 250 / 255, green: 236 / 255, blue: 190 / 255, alpha: 1)]), "огрызок яблока"),
    ]

    static let poop = PixelArt(rows: ["..B...", ".BBB..", ".BBBB.", "BBBBBB"],
                               palette: ["B": NSColor(srgbRed: 128 / 255, green: 82 / 255, blue: 48 / 255, alpha: 1)])
}

/// Мячик: падает, отскакивает от кромок окон, пола и краёв экрана. Его можно схватить курсором
/// и кинуть — улетит со скоростью руки. Питомец носит его в зубах. Физика идёт по своему таймеру,
/// чтобы с двумя питомцами мячик не летал вдвое быстрее; кромки и тяжесть ему подсказывают питомцы.
@MainActor
final class Ball {
    private let prop = Prop(clickable: true)
    private(set) var isActive = false
    private(set) var isGrabbed = false
    /// Кто держит в зубах.
    weak var carrier: AnyObject?
    var inMouth: Bool { carrier != nil }
    var position = NSPoint.zero
    var velocity = CGVector.zero
    /// Когда мячик в последний раз трогали руками — от этого зависит, интересен ли он питомцу.
    private(set) var touchedAt = Date.distantPast
    private var grabOffset = NSPoint.zero
    private var trail: [(Date, NSPoint)] = []
    var pixel: CGFloat = 3
    var radius: CGFloat { pixel * 3.5 }
    var platforms: [Platform] = []
    var gravity: CGFloat = 2600
    private var timer: Timer?
    private var lastStep = Date()

    init() {
        prop.view.onMouseDown = { [unowned self] in grab() }
        prop.view.onMouseDragged = { [unowned self] in drag() }
        prop.view.onMouseUp = { [unowned self] in release() }
    }

    func spawn(at point: NSPoint) {
        isActive = true
        carrier = nil
        position = point
        velocity = CGVector(dx: .random(in: -150...150), dy: 200)
        touchedAt = Date()
        show()
        lastStep = Date()
        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = Date()
                self.step(CGFloat(min(now.timeIntervalSince(self.lastStep), 0.1)))
                self.lastStep = now
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func remove() {
        timer?.invalidate()
        timer = nil
        isActive = false
        isGrabbed = false
        carrier = nil
        prop.hide()
    }

    private func grab() {
        isGrabbed = true
        carrier = nil
        velocity = .zero
        let m = NSEvent.mouseLocation
        grabOffset = NSPoint(x: position.x - m.x, y: position.y - m.y)
        trail = [(Date(), m)]
    }

    private func drag() {
        let m = NSEvent.mouseLocation
        position = NSPoint(x: m.x + grabOffset.x, y: m.y + grabOffset.y)
        trail.append((Date(), m))
        trail.removeAll { Date().timeIntervalSince($0.0) > 0.1 }
        show()
    }

    /// Бросок: скорость руки за последнюю десятую долю секунды.
    private func release() {
        isGrabbed = false
        touchedAt = Date()
        if let first = trail.first, let last = trail.last, last.0.timeIntervalSince(first.0) > 0.005 {
            let dt = CGFloat(last.0.timeIntervalSince(first.0))
            velocity = CGVector(dx: (last.1.x - first.1.x) / dt, dy: (last.1.y - first.1.y) / dt)
            let speed = hypot(velocity.dx, velocity.dy), limit: CGFloat = 5000
            if speed > limit { velocity = CGVector(dx: velocity.dx * limit / speed, dy: velocity.dy * limit / speed) }
        }
    }

    private func step(_ dt: CGFloat) {
        guard isActive, !isGrabbed, !inMouth else {
            if isActive { show() }
            return
        }
        let prevBottom = position.y - radius
        velocity.dy -= gravity * dt
        position.x += velocity.dx * dt
        position.y += velocity.dy * dt
        let bottom = position.y - radius
        if velocity.dy <= 0, let floor = platforms
            .filter({ $0.holds(position.x) && prevBottom >= $0.y - 0.5 && bottom <= $0.y })
            .max(by: { $0.y < $1.y }) {
            position.y = floor.y + radius
            velocity.dy = abs(velocity.dy) < 120 ? 0 : -velocity.dy * 0.6
            velocity.dx *= velocity.dy == 0 ? max(0, 1 - 3 * dt) : 0.85  // катится и тормозит
        }
        // Рикошет от краёв экранов; если провалился ниже пола — на пол
        let screens = NSScreen.screens.map(\.visibleFrame)
        if let minX = screens.map(\.minX).min(), let maxX = screens.map(\.maxX).max(),
           let minY = screens.map(\.minY).min(), let maxY = screens.map(\.maxY).max() {
            if position.x - radius < minX {
                position.x = minX + radius
                velocity.dx = abs(velocity.dx) * 0.8
            } else if position.x + radius > maxX {
                position.x = maxX - radius
                velocity.dx = -abs(velocity.dx) * 0.8
            }
            if position.y + radius > maxY {
                position.y = maxY - radius
                velocity.dy = -abs(velocity.dy) * 0.6
            } else if position.y - radius < minY {
                position.y = minY + radius
                velocity.dy = 0
            }
        }
        show()
    }

    var isResting: Bool { !isGrabbed && !inMouth && velocity.dy == 0 && abs(velocity.dx) < 20 }

    func show() {
        prop.show(Arts.ball, center: position, pixel: pixel)
        if inMouth { prop.panel.orderFrontRegardless() }  // поверх питомца, чтобы было видно в зубах
    }
}

/// Бабочка: прилетает из-за края экрана, порхает вокруг точки, улетает.
@MainActor
final class Butterfly {
    private let prop = Prop()
    private(set) var isActive = false
    private(set) var position = NSPoint.zero
    /// Куда летит; nil — улетает прочь, вверх и в сторону.
    var target: NSPoint?
    private var awayDir: CGFloat = 1
    private var start = Date()
    var pixel: CGFloat = 3

    func spawn(from point: NSPoint, toward target: NSPoint) {
        isActive = true
        position = point
        self.target = target
        start = Date()
    }

    func flyAway() {
        awayDir = Bool.random() ? 1 : -1
        target = nil
    }

    func remove() {
        isActive = false
        prop.hide()
    }

    func step(_ dt: CGFloat) {
        guard isActive else { return }
        let t = Date().timeIntervalSince(start)
        let speed = pixel * 30
        let goal = target.map { NSPoint(x: $0.x + sin(t * 1.7) * pixel * 8, y: $0.y + sin(t * 2.3) * pixel * 5) }
            ?? NSPoint(x: position.x + awayDir * 1000, y: position.y + 600)
        let dx = goal.x - position.x, dy = goal.y - position.y, d = max(hypot(dx, dy), 1)
        let v = min(speed, d * 3)
        position.x += dx / d * v * dt
        position.y += dy / d * v * dt + sin(t * 9) * pixel * 6 * dt  // порхает вверх-вниз
        let frame = Arts.butterfly[Int(t / 0.12) % 2]
        prop.show(frame, center: position, pixel: pixel)
        // Улетела за край — всё
        if target == nil && !NSScreen.screens.contains(where: { $0.frame.insetBy(dx: -40, dy: -40).contains(position) }) {
            remove()
        }
    }
}
