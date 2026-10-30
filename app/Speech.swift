import AppKit

/// Пузырь с репликой над головой питомца. Цвета как у спрайтов, не зависят от темы macOS. Клик — закрыть.
/// Липкий пузырь (напоминание) сам не исчезает и не перебивается болтовнёй.
@MainActor
final class SpeechBubble {
    static let ink = NSColor(srgbRed: 43 / 255, green: 29 / 255, blue: 26 / 255, alpha: 1)
    static let paper = NSColor(srgbRed: 1, green: 246 / 255, blue: 232 / 255, alpha: 1)

    private let panel: NSPanel
    private let view = BubbleView()
    private let label = NSTextField(labelWithString: "")
    private var hideAt: Date?

    private let padding: CGFloat = 10
    private let maxWidth: CGFloat = 260

    var isVisible: Bool { panel.isVisible }
    private(set) var isSticky = false

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = view
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        view.addSubview(label)
        view.onClick = { [weak self] in self?.hide() }
    }

    func show(_ text: NSAttributedString, sticky: Bool = false) {
        isSticky = sticky
        label.attributedStringValue = text
        label.preferredMaxLayoutWidth = maxWidth
        let fit = label.sizeThatFits(NSSize(width: maxWidth, height: 1000))
        let size = NSSize(width: ceil(fit.width) + padding * 2, height: ceil(fit.height) + padding * 2 + BubbleView.tail)
        panel.setContentSize(size)
        view.frame = NSRect(origin: .zero, size: size)
        label.frame = NSRect(x: padding, y: BubbleView.tail + padding, width: ceil(fit.width), height: ceil(fit.height))
        hideAt = sticky ? nil : Date().addingTimeInterval(min(3 + Double(text.length) * 0.06, 12))
        panel.orderFrontRegardless()
    }

    func hide() {
        hideAt = nil
        isSticky = false
        panel.orderOut(nil)
    }

    /// Хвостик смотрит на голову питомца; сам пузырь не вылезает за края экрана.
    func follow(head: NSPoint, within area: NSRect) {
        guard panel.isVisible else { return }
        if let hideAt, Date() >= hideAt {
            hide()
            return
        }
        let size = panel.frame.size
        let x = min(max(head.x - size.width / 2, area.minX + 4), area.maxX - size.width - 4)
        let y = min(head.y + 2, area.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        let tailX = min(max(head.x - x, 14), size.width - 14)
        if view.tailX != tailX {
            view.tailX = tailX
            view.needsDisplay = true
        }
    }
}

/// Фон пузыря с хвостиком к голове; на нём же форма напоминания.
final class BubbleView: NSView {
    static let tail: CGFloat = 9
    var tailX: CGFloat = 20
    var onClick: (() -> Void)?

    override func draw(_ dirtyRect: NSRect) {
        let body = NSRect(x: 1, y: Self.tail, width: bounds.width - 2, height: bounds.height - Self.tail - 1)
        let box = NSBezierPath(roundedRect: body, xRadius: 6, yRadius: 6)
        box.lineWidth = 2
        SpeechBubble.paper.setFill()
        SpeechBubble.ink.setStroke()
        box.fill()
        box.stroke()

        // Хвостик поверх нижней кромки: заливка закрывает её кусок, обводятся только косые стороны
        let left = NSPoint(x: tailX - 6, y: Self.tail + 1.5), right = NSPoint(x: tailX + 6, y: Self.tail + 1.5)
        let tip = NSPoint(x: tailX - 2, y: 1)
        let fill = NSBezierPath()
        fill.move(to: left)
        fill.line(to: tip)
        fill.line(to: right)
        fill.close()
        fill.fill()
        let edges = NSBezierPath()
        edges.lineWidth = 2
        edges.move(to: NSPoint(x: left.x, y: Self.tail))
        edges.line(to: tip)
        edges.line(to: NSPoint(x: right.x, y: Self.tail))
        edges.stroke()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { onClick?() }
}
