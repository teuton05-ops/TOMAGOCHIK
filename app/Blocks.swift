import AppKit
import ApplicationServices

/// Номер окна CoreGraphics для окна Accessibility. Закрытая, но стабильная функция, её используют все оконные менеджеры.
@_silgen_name("_AXUIElementGetWindow")
private func _AXUIElementGetWindow(_ element: AXUIElement, _ id: UnsafeMutablePointer<CGWindowID>) -> AXError

/// Блоки переднего окна: картинки, ссылки-карточки, кнопки и поля ввода.
/// Координаты CoreGraphics (y вниз) на момент обхода; рамка окна нужна, чтобы блоки ехали вместе с ним.
struct Blocks {
    var windowID: CGWindowID
    var windowFrame: CGRect
    var rects: [CGRect]
}

/// Раз в ~0.7 с в фоне обходит дерево Accessibility переднего окна. Нужен доступ «Универсальный доступ».
@MainActor
final class BlockScanner {
    private(set) var latest: Blocks?
    private var busy = false
    private var lastScan = Date.distantPast
    private let queue = DispatchQueue(label: "tamagochi.blocks", qos: .utility)

    static var trusted: Bool { AXIsProcessTrusted() }

    static func requestAccess() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    func refresh(minWidth: CGFloat) {
        guard !busy, Date().timeIntervalSince(lastScan) > 0.7 else { return }
        guard Self.trusted else {
            latest = nil
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier
        else { return }
        busy = true
        lastScan = Date()
        let pid = app.processIdentifier
        queue.async {
            let blocks = BlockScanner.collect(pid: pid, minWidth: minWidth)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.latest = blocks
                    self.busy = false
                }
            }
        }
    }

    // MARK: - Обход дерева (фоновый поток)

    /// Платформы — только то, что всегда видно. Обычные контейнеры (AXGroup, div'ы раскладки) чаще всего
    /// прозрачные, а есть ли у них фон, Accessibility не говорит — иначе питомец стоит в пустоте.
    nonisolated private static let blockRoles: Set<String> = [
        "AXImage", "AXLink", "AXButton", "AXTextField", "AXTextArea", "AXComboBox", "AXPopUpButton", "AXMenuButton",
    ]
    /// Внутрь этих элементов не спускаемся: сами они блок, а внутри только текст и иконки.
    nonisolated private static let leafRoles: Set<String> = [
        "AXStaticText", "AXImage", "AXButton", "AXTextField", "AXTextArea", "AXCheckBox", "AXRadioButton",
        "AXPopUpButton", "AXComboBox", "AXSlider", "AXMenuButton", "AXLink", "AXScrollBar",
    ]

    nonisolated private static func collect(pid: pid_t, minWidth: CGFloat) -> Blocks? {
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Chrome и Electron-приложения строят дерево страницы, только когда их об этом попросят
        AXUIElementSetAttributeValue(app, "AXManualAccessibility" as CFString, kCFBooleanTrue)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &value) == .success,
              let value, CFGetTypeID(value) == AXUIElementGetTypeID()
        else { return nil }
        let window = value as! AXUIElement
        var windowID: CGWindowID = 0
        guard _AXUIElementGetWindow(window, &windowID) == .success, windowID != 0 else { return nil }
        let (_, frame, children) = info(window)
        guard let windowFrame = frame else { return nil }

        // Ниже заголовка окна и выше нижней кромки
        let content = CGRect(x: windowFrame.minX, y: windowFrame.minY + 28,
                             width: windowFrame.width, height: windowFrame.height - 36)
        var rects: [CGRect] = []
        var pending = children
        var next = 0
        let deadline = Date().addingTimeInterval(0.4)
        while next < pending.count, next < 4000, Date() < deadline {
            let (role, frame, children) = info(pending[next])
            next += 1
            if let frame {
                guard frame.intersects(windowFrame) else { continue }  // прокручено за пределы окна — всё поддерево тоже
                if blockRoles.contains(role), frame.width >= minWidth, frame.height >= 24,
                   frame.width <= windowFrame.width * 0.97,
                   content.contains(CGPoint(x: frame.midX, y: frame.minY)) {
                    rects.append(frame)
                }
            }
            if !leafRoles.contains(role) { pending.append(contentsOf: children) }
        }
        return Blocks(windowID: windowID, windowFrame: windowFrame, rects: rects)
    }

    /// Роль, рамка и дети одним запросом к приложению.
    nonisolated private static func info(_ element: AXUIElement) -> (String, CGRect?, [AXUIElement]) {
        let names = [kAXRoleAttribute, kAXPositionAttribute, kAXSizeAttribute, kAXChildrenAttribute] as CFArray
        var out: CFArray?
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &out) == .success,
              let values = out as? [AnyObject], values.count == 4
        else { return ("", nil, []) }
        var frame: CGRect?
        var origin = CGPoint.zero, size = CGSize.zero
        if CFGetTypeID(values[1]) == AXValueGetTypeID(), CFGetTypeID(values[2]) == AXValueGetTypeID(),
           AXValueGetValue(values[1] as! AXValue, .cgPoint, &origin),
           AXValueGetValue(values[2] as! AXValue, .cgSize, &size) {
            frame = CGRect(origin: origin, size: size)
        }
        return (values[0] as? String ?? "", frame, values[3] as? [AXUIElement] ?? [])
    }
}
