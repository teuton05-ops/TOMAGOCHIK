import AppKit

/// Форма нового напоминания в пузыре над питомцем. Дата подхватывается из текста
/// («через 20 минут…», «завтра в 10…»), её можно поправить руками.
/// Enter — сохранить, Esc или клик мимо — закрыть.
@MainActor
final class ReminderForm: NSObject, NSTextFieldDelegate, NSWindowDelegate {
    private let panel = KeyPanel()
    private let bubble = BubbleView()
    private let title = NSTextField(labelWithString: "О чём напомнить?")
    private let field = NSTextField()
    private let picker = NSDatePicker()
    private let whenLabel = NSTextField(labelWithString: "")
    private let hint = NSTextField(labelWithString: "↩ — запомнить, esc — отмена")
    private let save = NSButton(title: "Напомнить", target: nil, action: nil)

    var onSave: ((String, Date) -> Void)?
    var onClose: (() -> Void)?
    var isVisible: Bool { panel.isVisible }

    private let width: CGFloat = 310
    private let pad: CGFloat = 12

    override init() {
        super.init()
        panel.delegate = self
        panel.onCancel = { [weak self] in self?.close() }
        panel.contentView = bubble

        title.font = .systemFont(ofSize: 13, weight: .semibold)
        title.textColor = SpeechBubble.ink
        field.placeholderString = "через 20 минут позвонить маме"
        field.font = .systemFont(ofSize: 13)
        field.delegate = self
        picker.datePickerStyle = .textFieldAndStepper
        picker.datePickerElements = [.yearMonthDay, .hourMinute]
        picker.locale = Locale(identifier: "ru_RU")
        picker.target = self
        picker.action = #selector(pickerChanged)
        picker.sizeToFit()
        for label in [whenLabel, hint] {
            label.font = .systemFont(ofSize: 11)
            label.textColor = SpeechBubble.ink.withAlphaComponent(0.6)
        }
        save.bezelStyle = .rounded
        save.keyEquivalent = "\r"
        save.target = self
        save.action = #selector(commit)
        save.sizeToFit()

        [title, field, picker, whenLabel, hint, save].forEach(bubble.addSubview)
        layout()
    }

    private func layout() {
        var y = BubbleView.tail + pad
        save.frame.origin = NSPoint(x: width - pad - save.frame.width, y: y - 2)
        hint.sizeToFit()
        hint.frame.origin = NSPoint(x: pad, y: y + 4)
        y += 30
        picker.frame.origin = NSPoint(x: pad, y: y)
        whenLabel.frame = NSRect(x: picker.frame.maxX + 8, y: y + 4, width: width - picker.frame.maxX - 8 - pad, height: 16)
        y += picker.frame.height + 8
        field.frame = NSRect(x: pad, y: y, width: width - pad * 2, height: 24)
        y += 30
        title.sizeToFit()
        title.frame.origin = NSPoint(x: pad, y: y)
        y += title.frame.height + pad
        panel.setContentSize(NSSize(width: width, height: y))
        bubble.frame = NSRect(x: 0, y: 0, width: width, height: y)
    }

    /// Открыть над головой питомца, не вылезая за край экрана.
    func show(head: NSPoint, within area: NSRect) {
        field.stringValue = ""
        picker.dateValue = Date().addingTimeInterval(15 * 60)
        updateWhen()
        let size = panel.frame.size
        let x = min(max(head.x - size.width / 2, area.minX + 4), area.maxX - size.width - 4)
        let y = min(head.y + 2, area.maxY - size.height)
        panel.setFrameOrigin(NSPoint(x: x, y: y))
        bubble.tailX = min(max(head.x - x, 14), size.width - 14)
        bubble.needsDisplay = true
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(field)
    }

    func close() {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        onClose?()
    }

    // MARK: - Действия

    @objc private func commit() {
        let parsed = ReminderParser.parse(field.stringValue)
        let text = parsed.text.isEmpty ? field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) : parsed.text
        let date = picker.dateValue
        guard !text.isEmpty, date > Date() else {
            NSSound.beep()
            return
        }
        onSave?(text, date)
        close()
    }

    @objc private func pickerChanged() {
        updateWhen()
    }

    private func updateWhen() {
        let date = picker.dateValue
        whenLabel.stringValue = date > Date() ? Reminders.when(date) : "уже прошло"
    }

    // MARK: - Делегаты

    func controlTextDidChange(_ obj: Notification) {
        if let date = ReminderParser.parse(field.stringValue).date {
            picker.dateValue = date
            updateWhen()
        }
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.insertNewline(_:)):
            commit()
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }
}

/// Панель поверх всех окон, в которую можно печатать, не уводя фокус у переднего приложения.
private final class KeyPanel: NSPanel {
    var onCancel: (() -> Void)?

    init() {
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        appearance = NSAppearance(named: .aqua)  // цвета пузыря не зависят от темы
    }

    override var canBecomeKey: Bool { true }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}
