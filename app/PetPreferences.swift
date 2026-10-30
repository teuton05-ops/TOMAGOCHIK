import Foundation

/// Один снимок настроек для окна и быстрых команд меню.
struct PetPreferences: Equatable {
    var selection: String
    var scale: Double
    var blocks: Bool
    var chatter: Bool
    var music: Bool
    var screenshots: Bool
    var catCoat: PetCoat = .original
    var dogCoat: PetCoat = .original
    var opacity: Double = 1
    var speed: Double = 1
    var sleepMinutes: Double = 5
    var chasesCursor: Bool = true
    var chatFrequency: Double = 1
    var reminderSound: Bool = true
    var cornerMode = false
    var cornerSide = "right"

    static let standard = PetPreferences(selection: "cat", scale: 2, blocks: true,
                                         chatter: true, music: true, screenshots: true)

    var normalized: PetPreferences {
        var p = self
        if !["cat", "dog", "duo"].contains(p.selection) { p.selection = "cat" }
        func bounded(_ value: Double, _ range: ClosedRange<Double>, _ fallback: Double) -> Double {
            value.isFinite ? min(range.upperBound, max(range.lowerBound, value)) : fallback
        }
        p.scale = bounded(p.scale, 1...4, 2)
        p.opacity = bounded(p.opacity, 0.35...1, 1)
        p.speed = bounded(p.speed, 0.5...2, 1)
        if ![0,1,3,5,10,15,30].contains(p.sleepMinutes) { p.sleepMinutes = 5 }
        if ![0.5,1,2].contains(p.chatFrequency) { p.chatFrequency = 1 }
        if !["left", "right"].contains(p.cornerSide) { p.cornerSide = "right" }
        return p
    }

    static func load(_ defaults: UserDefaults) -> PetPreferences {
        var p = standard
        p.selection = defaults.bool(forKey: "duo") ? "duo" : defaults.string(forKey: "species") ?? "cat"
        p.scale = defaults.object(forKey: "scale48") == nil
            ? [2: 1.5, 3: 2, 4: 2.5][defaults.double(forKey: "scale")] ?? 2
            : defaults.double(forKey: "scale48")
        p.blocks = defaults.object(forKey: "blocks") as? Bool ?? true
        p.chatter = defaults.object(forKey: "chatter") as? Bool ?? true
        p.music = defaults.object(forKey: "musicEnabled") as? Bool ?? true
        p.screenshots = defaults.object(forKey: "screenshotsEnabled") as? Bool ?? true
        p.catCoat = PetCoat(rawValue: defaults.string(forKey: "catCoat") ?? "") ?? .original
        p.dogCoat = PetCoat(rawValue: defaults.string(forKey: "dogCoat") ?? "") ?? .original
        p.opacity = defaults.object(forKey: "petOpacity") as? Double ?? 1
        p.speed = defaults.object(forKey: "movementSpeed") as? Double ?? 1
        p.sleepMinutes = defaults.object(forKey: "sleepMinutes") as? Double ?? 5
        p.chasesCursor = defaults.object(forKey: "chasesCursor") as? Bool ?? true
        p.chatFrequency = defaults.object(forKey: "chatFrequency") as? Double ?? 1
        p.reminderSound = defaults.object(forKey: "reminderSound") as? Bool ?? true
        p.cornerMode = defaults.object(forKey: "cornerMode") as? Bool ?? false
        p.cornerSide = defaults.string(forKey: "cornerSide") ?? "right"
        return p.normalized
    }

    func save(_ defaults: UserDefaults) {
        let p = normalized
        defaults.set(p.selection == "duo", forKey: "duo")
        if p.selection != "duo" { defaults.set(p.selection, forKey: "species") }
        defaults.set(p.scale, forKey: "scale48")
        defaults.set(p.blocks, forKey: "blocks")
        defaults.set(p.chatter, forKey: "chatter")
        defaults.set(p.music, forKey: "musicEnabled")
        defaults.set(p.screenshots, forKey: "screenshotsEnabled")
        defaults.set(p.catCoat.rawValue, forKey: "catCoat")
        defaults.set(p.dogCoat.rawValue, forKey: "dogCoat")
        defaults.set(p.opacity, forKey: "petOpacity")
        defaults.set(p.speed, forKey: "movementSpeed")
        defaults.set(p.sleepMinutes, forKey: "sleepMinutes")
        defaults.set(p.chasesCursor, forKey: "chasesCursor")
        defaults.set(p.chatFrequency, forKey: "chatFrequency")
        defaults.set(p.reminderSound, forKey: "reminderSound")
        defaults.set(p.cornerMode, forKey: "cornerMode")
        defaults.set(p.cornerSide, forKey: "cornerSide")
    }
}

