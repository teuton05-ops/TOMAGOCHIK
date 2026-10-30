import AppKit

/// Рисует текущий кадр без сглаживания и отдаёт клики питомцу.
/// Прозрачные пиксели окна macOS пропускает насквозь, так что ловятся только клики по самому зверьку.
/// Ещё принимает брошенные на питомца файлы и даёт вытащить их у него из зубов.
@MainActor
final class PetView: NSView, NSDraggingSource {
    weak var pet: Pet?
    var menuProvider: (() -> NSMenu)?
    var coat: PetCoat = .original {
        didSet {
            if coat != oldValue { clearAppearanceCache() }
        }
    }
    var spriteOpacity: CGFloat = 1 { didSet { needsDisplay = true } }
    // Сохраняем и исходник: его ObjectIdentifier не переиспользуется для другого кадра.
    private var paintedFrames: [ObjectIdentifier: (source: CGImage, result: CGImage)] = [:]

    func clearAppearanceCache() {
        paintedFrames.removeAll()
        needsDisplay = true
    }

    /// Файлы в зубах; иконка первого рисуется у рта.
    var held: [URL] = [] {
        didSet {
            heldIcon = held.first.map { NSWorkspace.shared.icon(forFile: $0.path) }
            needsDisplay = true
        }
    }

    private var image: CGImage?
    private var facingLeft = false
    /// Поворот (радианы, против часовой): маятник за шкирку с осью у загривка или четверть оборота на стене.
    private var tilt: CGFloat = 0
    /// Высота оси поворота в долях спрайта от низа.
    private var pivotY: CGFloat = 0.6
    /// Растяжение по вертикали (по горизонтали — обратное), вокруг центра: в полёте.
    private var stretch: CGFloat = 1
    private var heldIcon: NSImage?
    private var grabOffset = NSPoint.zero
    private var dragged = false
    /// Схватили за файл, а не за питомца: тянем файл наружу.
    private var grabbedFile = false
    private var fileOut = false
    /// Одиночный клик ждёт, не будет ли второго: иначе питомец подпрыгнет и второй клик промахнётся.
    private var pendingClick: DispatchWorkItem?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    func show(_ image: CGImage, facingLeft: Bool, tilt: CGFloat = 0, pivotY: CGFloat = 0.6, stretch: CGFloat = 1) {
        guard image !== self.image || facingLeft != self.facingLeft || abs(tilt - self.tilt) > 0.002 || pivotY != self.pivotY
            || abs(stretch - self.stretch) > 0.005
        else { return }
        self.image = image
        self.facingLeft = facingLeft
        self.tilt = tilt
        self.pivotY = pivotY
        self.stretch = stretch
        needsDisplay = true
    }

    /// Где висит файл: у рта (в спрайте рот около x 22, y 18 сверху), чуть ниже и впереди.
    private var heldRect: NSRect {
        let side = bounds.width * 0.42
        let mouthX = bounds.width * (22.5 / 32) + side * 0.15
        let x = facingLeft ? bounds.width - mouthX : mouthX
        let y = bounds.height * (13.5 / 32) - side * 0.25
        return NSRect(x: x - side / 2, y: y - side / 2, width: side, height: side)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let image, let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clear(bounds)
        ctx.saveGState()
        ctx.interpolationQuality = .none
        if tilt != 0 {
            let pivot = NSPoint(x: bounds.midX, y: bounds.height * pivotY)
            ctx.translateBy(x: pivot.x, y: pivot.y)
            ctx.rotate(by: tilt)
            ctx.translateBy(x: -pivot.x, y: -pivot.y)
        }
        if stretch != 1 {
            ctx.translateBy(x: bounds.midX, y: bounds.midY)
            ctx.scaleBy(x: 1 / stretch, y: stretch)
            ctx.translateBy(x: -bounds.midX, y: -bounds.midY)
        }
        if facingLeft {
            ctx.translateBy(x: bounds.width, y: 0)
            ctx.scaleBy(x: -1, y: 1)
        }
        let painted: CGImage
        if coat == .original {
            painted = image
        } else if let cached = paintedFrames[ObjectIdentifier(image)] {
            painted = cached.result
        } else {
            painted = coat.render(image)
            paintedFrames[ObjectIdentifier(image)] = (image, painted)
        }
        ctx.setAlpha(spriteOpacity)
        ctx.draw(painted, in: bounds)
        ctx.restoreGState()

        guard let heldIcon, !fileOut else { return }
        let rect = heldRect
        heldIcon.draw(in: rect)
        if held.count > 1 {
            let badge = NSRect(x: rect.maxX - 14, y: rect.maxY - 14, width: 16, height: 16)
            SpeechBubble.ink.setFill()
            NSBezierPath(ovalIn: badge).fill()
            let text = NSAttributedString(string: "\(held.count)", attributes: [
                .font: NSFont.systemFont(ofSize: 10, weight: .bold), .foregroundColor: NSColor.white,
            ])
            let size = text.size()
            text.draw(at: NSPoint(x: badge.midX - size.width / 2, y: badge.midY - size.height / 2))
        }
    }

    // MARK: - Мышь

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        let mouse = NSEvent.mouseLocation
        let origin = window?.frame.origin ?? .zero
        grabOffset = NSPoint(x: mouse.x - origin.x, y: mouse.y - origin.y)
        dragged = false
        grabbedFile = !held.isEmpty  // с файлом в зубах тянем за любое место — отдаёт файл
    }

    override func mouseDragged(with event: NSEvent) {
        if grabbedFile {
            if !dragged { pullFileOut(event) }
            dragged = true
            return
        }
        if !dragged {
            dragged = true
            pet?.pickUp()
        }
        let mouse = NSEvent.mouseLocation
        pet?.drag(to: NSPoint(x: mouse.x - grabOffset.x, y: mouse.y - grabOffset.y))
    }

    override func mouseUp(with event: NSEvent) {
        if grabbedFile && dragged { return }
        if dragged {
            pet?.drop()
            return
        }
        pendingClick?.cancel()
        if event.clickCount >= 2 {
            pet?.doubleClick()
            return
        }
        let click = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.pet?.poke() }
        }
        pendingClick = click
        DispatchQueue.main.asyncAfter(deadline: .now() + NSEvent.doubleClickInterval, execute: click)
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let menu = menuProvider?() else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    // MARK: - Файл из зубов

    private func pullFileOut(_ event: NSEvent) {
        let items = held.map { url in
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            item.setDraggingFrame(heldRect, contents: NSWorkspace.shared.icon(forFile: url.path))
            return item
        }
        fileOut = true
        needsDisplay = true
        beginDraggingSession(with: items, event: event, source: self)
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.copy, .move, .link, .generic] : []
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        fileOut = false
        needsDisplay = true
        if !operation.isEmpty { pet?.letGo() }  // забрали — отпускает; бросили в пустоту — держит дальше
    }

    // MARK: - Файл в зубы

    private func fileURLs(_ info: NSDraggingInfo) -> [URL] {
        info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard pet?.acceptsFiles == true, sender.draggingSource as? PetView !== self, !fileURLs(sender).isEmpty else { return [] }
        pet?.noticeIncomingFile()
        return .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(sender)
        guard !urls.isEmpty else { return false }
        pet?.hold(urls)
        return true
    }
}
