import AppKit

/// Иконка-лапка в строке меню: файл в зубах (конвертировать, достать текст, убрать фон, сжать), напоминания, мячик, выбор питомца, размер, выход.
/// То же меню — по правому клику на питомце. Двойной клик — новое напоминание.
/// Пока открыто меню или форма, питомец стоит на месте, чтобы не убегать из-под курсора.
/// «Котик и собака» — второй питомец рядом: свой мячик у них общий, болтают по очереди.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let defaults = UserDefaults.standard
    private var pet: Pet!
    /// Второй питомец, когда выбраны оба.
    private var companion: Pet?
    private var pets: [Pet] { [pet] + (companion.map { [$0] } ?? []) }
    private let ball = Ball()
    private let events = MacEvents()
    private let weather = Weather()
    private var chatter: Chatter!
    private let reminders = Reminders()
    private let form = ReminderForm()
    /// Идёт работа с файлами: новые не запускаем.
    private var busy = false
    private var menuOpen = false
    private var statusItem: NSStatusItem!

    /// Точек экрана на пиксель спрайта 48×48: на Retina это ровно 3, 4 и 5 точек экрана.
    private let sizes: [(String, CGFloat)] = [("Маленький", 1.5), ("Средний", 2), ("Большой", 2.5)]

    func applicationDidFinishLaunching(_ notification: Notification) {
        let species = Species(rawValue: defaults.string(forKey: "species") ?? "") ?? .cat
        // Размер из времён спрайтов 32×32 переводим в тот же размер на экране
        let stored = defaults.double(forKey: "scale48")
        let scale = stored > 0 ? stored : [2: 1.5, 3: 2, 4: 2.5][defaults.double(forKey: "scale")] ?? 2
        pet = Pet(species: species, scale: scale, ball: ball)
        pet.view.menuProvider = { [unowned self] in contextMenu() }
        pet.blocksEnabled = defaults.object(forKey: "blocks") as? Bool ?? true
        if pet.blocksEnabled && !BlockScanner.trusted { BlockScanner.requestAccess() }

        chatter = Chatter(pet: pet)
        pet.onDoubleClick = { [unowned self] in newReminder(at: pet) }
        form.onClose = { [unowned self] in updatePause() }
        form.onSave = { [unowned self] text, date in
            reminders.add(text, at: date)
            chatter.say("Запомнил! Напомню \(Reminders.when(date))")
        }
        reminders.onDue = { [unowned self] reminder in chatter.remind(reminder.text) }
        pet.onWake = { [unowned self] in chatter.welcomeBack() }
        pet.onPetted = { [unowned self] in chatter.purr() }
        pet.held = (defaults.stringArray(forKey: "held") ?? [])
            .filter { FileManager.default.fileExists(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
        lastHeld = pet.held
        Pet.requestAccess(to: pet.held)
        pet.onHeldChange = { [unowned self] held in heldChanged(held) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [unowned self] in chatter.greet() }
        events.onMusic = { [unowned self] playing in pets.forEach { $0.musicPlaying = playing } }
        events.onScreenshot = { [unowned self] in
            pets.forEach { $0.poseForPhoto() }
            chatter.say("Сыр! 📸")
        }
        events.onMacWake = { [unowned self] in
            pets.forEach { $0.macWoke() }
            chatter.say(Lines.macWake(pet.species))
        }
        events.onTrash = { [unowned self] in pet.goToTrash() }
        weather.onChange = { [unowned self] now in
            chatter.weather = now
            pets.forEach { $0.weather = now?.kind }
        }
        pet.onSay = { [unowned pet] text in pet.say(Chatter.plain(text)) }
        if defaults.bool(forKey: "duo") { setDuo(true) }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: "Тамагочи")
        let menu = NSMenu()
        menu.delegate = self  // пересобираем при каждом открытии: доступ могли выдать, пока меню было закрыто
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        fill(menu)
    }

    func menuWillOpen(_ menu: NSMenu) {
        menuOpen = true
        updatePause()
    }

    func menuDidClose(_ menu: NSMenu) {
        menuOpen = false
        // Пункт меню выполняется уже после закрытия: даём ему открыть форму, чтобы не отпустить питомца зря
        DispatchQueue.main.async { [unowned self] in updatePause() }
    }

    private func updatePause() {
        pets.forEach { $0.pause(menuOpen || form.isVisible) }
    }

    private func contextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        return menu
    }

    /// Позвать или отпустить второго питомца — другого вида, рядом с первым.
    private func setDuo(_ on: Bool) {
        if !on {
            companion?.dismiss()
            companion = nil
            chatter.friend = nil
            return
        }
        guard companion == nil else { return }
        let other: Species = pet.species == .cat ? .dog : .cat
        let friend = Pet(species: other, scale: pet.scale, ball: ball, x: pet.head.x + pet.size * 0.5)
        friend.acceptsFiles = false
        friend.blocksEnabled = pet.blocksEnabled
        friend.musicPlaying = events.musicPlaying
        friend.weather = weather.current?.kind
        friend.onSay = { [unowned friend] text in friend.say(Chatter.plain(text)) }
        friend.view.menuProvider = { [unowned self] in contextMenu() }
        friend.onDoubleClick = { [unowned self, unowned friend] in newReminder(at: friend) }
        friend.onPetted = { [unowned self, unowned friend] in chatter.purr(friend) }
        pet.friend = friend
        friend.friend = pet
        companion = friend
        chatter.friend = friend
    }

    private var lastHeld: [URL] = []

    private func heldChanged(_ held: [URL]) {
        defaults.set(held.map(\.path), forKey: "held")
        if held.count > lastHeld.count {
            let name = held.last!.lastPathComponent
            if !defaults.bool(forKey: "fileMenuHinted") {
                // Первый файл в жизни — сразу рассказать, что с ним можно сделать
                defaults.set(true, forKey: "fileMenuHinted")
                chatter.say("Держу «\(name)». Правый клик по мне — конвертирую, достану текст или сожму")
            } else {
                chatter.say(held.count == 1 ? "Держу «\(name)». Забирай, когда понадобится" : "Держу уже \(held.count) \(files(held.count))")
            }
        } else if held.isEmpty && !lastHeld.isEmpty {
            chatter.say("Держи!")
        }
        lastHeld = held
    }

    private func files(_ n: Int) -> String {
        let tens = n % 100, ones = n % 10
        if (11...14).contains(tens) { return "файлов" }
        return ones == 1 ? "файл" : (2...4).contains(ones) ? "файла" : "файлов"
    }

    private func fill(_ menu: NSMenu) {
        if !pet.held.isEmpty {
            let names = pet.held.map(\.lastPathComponent)
            let title = names.count == 1 ? "Во рту: \(names[0])" : "Во рту: \(names[0]) и ещё \(names.count - 1)"
            menu.addItem(NSMenuItem(title: title, action: nil, keyEquivalent: ""))
            menu.addItem(item("Показать в Finder", #selector(revealHeld)))
            menu.addItem(convertItem())
            menu.addItem(tool("Достать текст", #selector(extractText), pet.held.contains(where: Converter.canRecognizeText)))
            if Converter.canRemoveBackground {
                menu.addItem(tool("Убрать фон", #selector(removeBackground), pet.held.contains { Converter.kind(of: $0) == .image }))
            }
            menu.addItem(tool("Сжать для отправки", #selector(compress), pet.held.contains(where: Converter.canCompress)))
            menu.addItem(item("Выплюнуть", #selector(spitOut)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Новое напоминание…", #selector(newReminderFromMenu)))
        menu.addItem(item(pet.hasBall ? "Убрать мячик" : "Поиграть в мячик", #selector(toggleBall)))
        let upcoming = reminders.upcoming
        if !upcoming.isEmpty {
            let list = NSMenu()
            for r in upcoming {
                let entry = NSMenuItem(title: "\(Reminders.when(r.date)) — \(r.text)", action: nil, keyEquivalent: "")
                let actions = NSMenu()
                let delete = item("Удалить", #selector(deleteReminder(_:)))
                delete.representedObject = r.id
                actions.addItem(delete)
                entry.submenu = actions
                list.addItem(entry)
            }
            let listItem = NSMenuItem(title: "Напоминания (\(upcoming.count))", action: nil, keyEquivalent: "")
            listItem.submenu = list
            menu.addItem(listItem)
        }
        menu.addItem(.separator())
        for species in Species.allCases {
            let item = NSMenuItem(title: species.title, action: #selector(chooseSpecies(_:)), keyEquivalent: "")
            item.representedObject = species.rawValue
            item.state = companion == nil && pet.species == species ? .on : .off
            item.target = self
            menu.addItem(item)
        }
        let both = item("Котик и собака", #selector(chooseSpecies(_:)))
        both.representedObject = "duo"
        both.state = companion != nil ? .on : .off
        menu.addItem(both)
        menu.addItem(.separator())
        let sizeMenu = NSMenu()
        for (title, scale) in sizes {
            let item = NSMenuItem(title: title, action: #selector(chooseSize(_:)), keyEquivalent: "")
            item.representedObject = scale
            item.state = pet.scale == scale ? .on : .off
            item.target = self
            sizeMenu.addItem(item)
        }
        let sizeItem = NSMenuItem(title: "Размер", action: nil, keyEquivalent: "")
        sizeItem.submenu = sizeMenu
        menu.addItem(sizeItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    private func item(_ title: String, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    /// «Конвертировать в» с пятью форматами; неподходящие для файлов в зубах — серые.
    private func convertItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Конвертировать в", action: nil, keyEquivalent: "")
        guard !busy else { return item }  // без подменю и действия — серый
        let formats = NSMenu()
        formats.autoenablesItems = false
        for format in Format.allCases {
            let entry = self.item(format.rawValue, #selector(convert(_:)))
            entry.representedObject = format.rawValue
            entry.isEnabled = pet.held.contains { Converter.can($0, to: format) }
            formats.addItem(entry)
        }
        item.submenu = formats
        return item
    }

    /// Пункт действия над файлами; без действия меню само делает его серым.
    private func tool(_ title: String, _ action: Selector, _ applicable: Bool) -> NSMenuItem {
        let item = item(title, action)
        if busy || !applicable { item.action = nil }
        return item
    }

    /// Запускает работу с файлами в фоне: питомец говорит, что занят, а потом — чем кончилось.
    private func work(_ start: String, _ job: @escaping @MainActor () async -> String) {
        guard !busy else { return }
        busy = true
        chatter.say(start)
        Task {
            let result = await job()
            busy = false
            chatter.say(result)
        }
    }

    /// Новые файлы — в зубы вместо старых (оригиналы лежат на месте); фраза про итог.
    private func takeResults(_ done: [URL], failed: [String]) -> String {
        if !done.isEmpty { pet.held = done }
        var text = done.isEmpty ? "Не получилось" : done.count == 1 ? "Готово: «\(done[0].lastPathComponent)»" : "Готово: \(done.count) \(files(done.count))"
        if !failed.isEmpty && !done.isEmpty { text += ". Не вышло: \(failed.joined(separator: ", "))" }
        return text
    }

    @objc private func convert(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let format = Format(rawValue: raw) else { return }
        let held = pet.held
        work("Жую… будет \(format.rawValue)") { [unowned self] in
            let (done, failed) = await Converter.convert(held, to: format)
            return takeResults(done, failed: failed)
        }
    }

    @objc private func extractText() {
        let held = pet.held
        work("Читаю…") {
            let (text, failed) = await Converter.recognizeText(held)
            let clean = text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { return "Не нашёл текста" }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(clean, forType: .string)
            let start = clean.prefix(60).replacingOccurrences(of: "\n", with: " ")
            var result = "Скопировал \(clean.count) симв.: «\(start)\(clean.count > 60 ? "…" : "")»"
            if !failed.isEmpty { result += ". Пусто в: \(failed.joined(separator: ", "))" }
            return result
        }
    }

    @objc private func removeBackground() {
        let held = pet.held
        work("Аккуратно выгрызаю фон…") { [unowned self] in
            let (done, failed) = await Converter.removeBackground(held)
            return takeResults(done, failed: failed)
        }
    }

    @objc private func compress() {
        let held = pet.held
        work("Утрамбовываю…") { [unowned self] in
            let r = await Converter.compress(held)
            guard !r.done.isEmpty else { return r.small.isEmpty ? "Не получилось" : "Меньше не сделать, файлы и так компактные" }
            pet.held = r.done
            let bytes = ByteCountFormatter()
            var text = "Было \(bytes.string(fromByteCount: r.before)) → стало \(bytes.string(fromByteCount: r.after))"
            if !r.small.isEmpty { text += ". Уже компактные: \(r.small.joined(separator: ", "))" }
            if !r.failed.isEmpty { text += ". Не вышло: \(r.failed.joined(separator: ", "))" }
            return text
        }
    }

    @objc private func revealHeld() {
        NSWorkspace.shared.activateFileViewerSelecting(pet.held)
    }

    @objc private func spitOut() {
        pet.letGo()
    }

    @objc private func newReminderFromMenu() {
        newReminder(at: pet)
    }

    /// Форма над тем питомцем, по которому дважды кликнули.
    private func newReminder(at who: Pet) {
        guard !form.isVisible else { return }
        form.show(head: who.head, within: who.screenArea)
        updatePause()
    }

    @objc private func deleteReminder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID else { return }
        reminders.remove(id)
    }

    @objc private func toggleBall() {
        pet.toggleBall()
    }

    @objc private func chooseSpecies(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String else { return }
        if raw == "duo" {
            setDuo(true)
        } else if let species = Species(rawValue: raw) {
            setDuo(false)
            pet.species = species
            defaults.set(raw, forKey: "species")
        }
        defaults.set(companion != nil, forKey: "duo")
    }

    @objc private func chooseSize(_ sender: NSMenuItem) {
        guard let scale = sender.representedObject as? CGFloat else { return }
        pets.forEach { $0.scale = scale }
        defaults.set(Double(scale), forKey: "scale48")
    }
}

MainActor.assumeIsolated {
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
