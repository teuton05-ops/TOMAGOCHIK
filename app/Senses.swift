import AppKit
import Carbon.HIToolbox

/// Что происходит на Маке: играет ли музыка, не делают ли скриншот, проснулся ли Мак, не выбросили ли что-то в Корзину.
/// Музыка и Spotify сами рассылают уведомления о воспроизведении — разрешения не нужны.
/// Сочетания ⇧⌘3/4/5 видны, только если дан «Универсальный доступ»; без него ловим запуск
/// окна скриншотов (⇧⌘5 и «Снимок экрана»). За Корзиной следим, если macOS даёт заглянуть в её папку
/// (нужен «Полный доступ к диску»); без него просто не узнаем.
@MainActor
final class MacEvents {
    var onMusic: ((Bool) -> Void)?
    var onScreenshot: (() -> Void)?
    var onMacWake: (() -> Void)?
    var onTrash: (() -> Void)?
    private var trashSource: DispatchSourceFileSystemObject?
    private var trashCount: Int?
    private var lastTrash = Date.distantPast
    private(set) var musicPlaying = false
    private var players: [String: Bool] = [:]
    private var keyMonitor: Any?
    private var lastShot = Date.distantPast

    init() {
        let center = DistributedNotificationCenter.default()
        for name in ["com.apple.Music.playerInfo", "com.apple.iTunes.playerInfo", "com.spotify.client.PlaybackStateChanged"] {
            center.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] note in
                let playing = note.userInfo?["Player State"] as? String == "Playing"
                MainActor.assumeIsolated { self?.player(name, playing: playing) }
            }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard ["com.apple.screencaptureui", "com.apple.Screenshot"].contains(app?.bundleIdentifier) else { return }
            MainActor.assumeIsolated { self?.screenshot() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.onMacWake?() }
        }
        watchTrash()
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard mods.contains([.command, .shift]),
                  [kVK_ANSI_3, kVK_ANSI_4, kVK_ANSI_5].contains(Int(event.keyCode)) else { return }
            MainActor.assumeIsolated { self?.screenshot() }
        }
    }

    private func player(_ name: String, playing: Bool) {
        players[name] = playing
        let now = players.values.contains(true)
        guard now != musicPlaying else { return }
        musicPlaying = now
        onMusic?(now)
    }

    /// Папка Корзины поменялась: файлов стало больше — что-то выбросили. Очистку Корзины пропускаем.
    private func watchTrash() {
        let path = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash").path
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let count = { (try? FileManager.default.contentsOfDirectory(atPath: path).count) }
        trashCount = count()
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: .write, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = count()
                defer { self.trashCount = now }
                if let now, let before = self.trashCount, now <= before { return }
                guard Date().timeIntervalSince(self.lastTrash) > 20 else { return }
                self.lastTrash = Date()
                self.onTrash?()
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        trashSource = source
    }

    /// Где на экране значок Корзины в Доке (координаты Cocoa). Нужен «Универсальный доступ».
    static func trashInDock() -> NSPoint? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first,
              let primary = NSScreen.screens.first
        else { return nil }
        func children(_ e: AXUIElement) -> [AXUIElement] {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(e, kAXChildrenAttribute as CFString, &value)
            return value as? [AXUIElement] ?? []
        }
        func string(_ e: AXUIElement, _ attr: String) -> String? {
            var value: CFTypeRef?
            AXUIElementCopyAttributeValue(e, attr as CFString, &value)
            return value as? String
        }
        for list in children(AXUIElementCreateApplication(dock.processIdentifier)) where string(list, kAXRoleAttribute) == kAXListRole {
            for item in children(list) where string(item, kAXSubroleAttribute) == "AXTrashDockItem" {
                var pos: CFTypeRef?, size: CFTypeRef?
                AXUIElementCopyAttributeValue(item, kAXPositionAttribute as CFString, &pos)
                AXUIElementCopyAttributeValue(item, kAXSizeAttribute as CFString, &size)
                var p = CGPoint.zero, sz = CGSize.zero
                guard let pos, let size, AXValueGetValue(pos as! AXValue, .cgPoint, &p), AXValueGetValue(size as! AXValue, .cgSize, &sz)
                else { return nil }
                return NSPoint(x: p.x + sz.width / 2, y: primary.frame.maxY - p.y - sz.height / 2)
            }
        }
        return nil
    }

    /// Одно позирование на снимок: ⇧⌘4 и запуск окна скриншотов приходят почти разом.
    private func screenshot() {
        guard Date().timeIntervalSince(lastShot) > 3 else { return }
        lastShot = Date()
        onScreenshot?()
    }
}
