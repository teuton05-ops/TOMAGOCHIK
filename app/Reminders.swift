import AppKit

struct Reminder: Codable, Equatable {
    var id = UUID()
    var text: String
    var date: Date
}

/// Список напоминаний в UserDefaults. Раз в секунду проверяет, не пора ли; пропущенные,
/// пока приложение не работало, срабатывают сразу после запуска.
@MainActor
final class Reminders {
    private let defaults = UserDefaults.standard
    private(set) var items: [Reminder] = []
    var onDue: ((Reminder) -> Void)?
    private var timer: Timer?
    /// Дать питомцу поздороваться, прежде чем вываливать пропущенное.
    private let startAt = Date().addingTimeInterval(3)

    init() {
        if let data = defaults.data(forKey: "reminders"),
           let saved = try? JSONDecoder().decode([Reminder].self, from: data) {
            items = saved
        }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Ближайшие сверху.
    var upcoming: [Reminder] { items.sorted { $0.date < $1.date } }

    func add(_ text: String, at date: Date) {
        items.append(Reminder(text: text, date: date))
        save()
    }

    func remove(_ id: UUID) {
        items.removeAll { $0.id == id }
        save()
    }

    private func check() {
        let now = Date()
        guard now >= startAt else { return }
        let due = items.filter { $0.date <= now }.sorted { $0.date < $1.date }
        guard !due.isEmpty else { return }
        items.removeAll { $0.date <= now }
        save()
        due.forEach { onDue?($0) }
    }

    private func save() {
        defaults.set(try? JSONEncoder().encode(items), forKey: "reminders")
    }

    /// «через 5 мин», «сегодня в 18:30», «завтра в 9:00», «3 нояб. в 10:00»; время в формате системы.
    nonisolated static func when(_ date: Date, now: Date = Date()) -> String {
        let cal = Calendar.current
        let minutes = date.timeIntervalSince(now) / 60
        if minutes > 0 && minutes < 60 { return "через \(max(1, Int(minutes.rounded()))) мин" }
        let at = "в \(DateFormatter.localizedString(from: date, dateStyle: .none, timeStyle: .short))"  // 12/24 ч — как в системе
        if cal.isDate(date, inSameDayAs: now) { return "сегодня \(at)" }
        let days = cal.dateComponents([.day], from: cal.startOfDay(for: now), to: cal.startOfDay(for: date)).day ?? 0
        if days == 1 { return "завтра \(at)" }
        if days == 2 { return "послезавтра \(at)" }
        let day = DateFormatter()
        day.locale = Locale(identifier: "ru_RU")
        day.dateFormat = cal.isDate(date, equalTo: now, toGranularity: .year) ? "d MMM" : "d MMM yyyy"
        return "\(day.string(from: date)) \(at)"
    }
}

/// Достаёт дату из фразы вроде «через 20 минут позвонить маме» или «завтра в 10 созвон»
/// и возвращает остаток текста без неё.
enum ReminderParser {
    struct Result {
        var text: String
        var date: Date?
    }

    static func parse(_ input: String, now: Date = Date(), calendar cal: Calendar = .current) -> Result {
        var text = input as NSString
        var cut: [NSRange] = []

        func match(_ pattern: String) -> NSTextCheckingResult? {
            let re = try! NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
            return re.firstMatch(in: text as String, range: NSRange(location: 0, length: text.length))
        }
        func group(_ m: NSTextCheckingResult, _ i: Int) -> String? {
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : text.substring(with: r).lowercased()
        }
        func finish(_ date: Date?) -> Result {
            for r in cut.sorted(by: { $0.location > $1.location }) {
                text = text.replacingCharacters(in: r, with: " ") as NSString
            }
            return Result(text: tidy(text as String), date: date)
        }

        // «через 20 минут», «через полчаса», «через пару часов», «через день»
        if let m = match(#"(?<![а-яё])через\s+(?:(\d+(?:[.,]\d+)?|пару|полтора|полторы|пол)\s*)?(секунд[а-яё]*|сек|минут[а-яё]*|мин|час[а-яё]*|ч|дн[а-яё]*|день|недел[а-яё]*|нед)(?![а-яё])\.?"#) {
            let amount: Double = switch group(m, 1) {
            case nil: 1
            case "пару": 2
            case "пол": 0.5
            case "полтора", "полторы": 1.5
            case let n?: Double(n.replacingOccurrences(of: ",", with: ".")) ?? 1
            }
            let unit = group(m, 2) ?? ""
            let seconds: Double = unit.hasPrefix("с") ? 1 : unit.hasPrefix("м") ? 60 : unit.hasPrefix("ч") ? 3600
                : unit.hasPrefix("н") ? 604_800 : 86400
            cut.append(m.range)
            return finish(now.addingTimeInterval(amount * seconds))
        }

        var dayOffset: Int?
        if let m = match(#"(?<![а-яё])(сегодня|завтра|послезавтра)(?![а-яё])"#) {
            dayOffset = ["сегодня": 0, "завтра": 1, "послезавтра": 2][group(m, 1) ?? ""]
            cut.append(m.range)
        }
        let weekdays = ["воскрес": 1, "понедельник": 2, "вторник": 3, "сред": 4, "четверг": 5, "пятниц": 6, "суббот": 7]
        if dayOffset == nil,
           let m = match(#"(?<![а-яё])(?:во?\s+)?(понедельник|вторник|среду|среда|четверг|пятницу|пятница|субботу|суббота|воскресенье)(?![а-яё])"#),
           let name = group(m, 1),
           let wd = weekdays.first(where: { name.hasPrefix($0.key) })?.value {
            let today = cal.component(.weekday, from: now)
            let ahead = (wd - today + 7) % 7
            dayOffset = ahead == 0 ? 7 : ahead
            cut.append(m.range)
        }

        var partHour: Int?
        if let m = match(#"(?<![а-яё])(утром|днём|днем|вечером|ночью)(?![а-яё])"#) {
            partHour = ["утром": 9, "днём": 13, "днем": 13, "вечером": 19, "ночью": 23][group(m, 1) ?? ""]
            cut.append(m.range)
        }

        // «в 18:30», «к 9.15», «в 7 вечера», «в 10 часов», «18:30»
        var time: (h: Int, m: Int, suffix: String?)?
        if let m = match(#"(?:(?<![а-яё])(?:в|к)\s+)?(?<!\d)(\d{1,2})[:.](\d{2})(?!\d)(?:\s+(утра|дня|вечера|ночи))?"#)
            ?? match(#"(?<![а-яё])(?:в|к)\s+(\d{1,2})()(?!\d)(?:\s*час[а-яё]*)?(?:\s+(утра|дня|вечера|ночи))?(?![а-яё])"#),
            var h = Int(group(m, 1) ?? ""), h <= 23 {
            let minute = Int(group(m, 2) ?? "") ?? 0
            let suffix = group(m, 3)
            switch suffix {
            case "дня", "вечера": if h < 12 { h += 12 }
            case "ночи": if h == 12 { h = 0 }
            default: if let partHour, partHour >= 13, h < 12 { h += 12 }  // «вечером в 7»
            }
            if minute <= 59 {
                time = (h, minute, suffix)
                cut.append(m.range)
            }
        }

        guard dayOffset != nil || time != nil || partHour != nil else { return finish(nil) }
        let base = cal.date(byAdding: .day, value: dayOffset ?? 0, to: cal.startOfDay(for: now))!
        var date = cal.date(bySettingHour: time?.h ?? partHour ?? 9, minute: time?.m ?? 0, second: 0, of: base)!
        if dayOffset == nil && date <= now {
            // «в 5» в два часа дня — это скорее 17:00, чем завтрашние 5 утра
            if let time, time.suffix == nil, partHour == nil, (1...11).contains(time.h),
               date.addingTimeInterval(12 * 3600) > now {
                date.addTimeInterval(12 * 3600)
            } else {
                date = cal.date(byAdding: .day, value: 1, to: date)!
            }
        }
        return finish(date)
    }

    /// Убирает «напомни мне», «что», висящие тире и лишние пробелы; первая буква — заглавная.
    private static func tidy(_ s: String) -> String {
        var t = s.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^\s*напомни(ть)?(\s+мне)?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        let edges = CharacterSet.whitespaces.union(CharacterSet(charactersIn: "—–-,:;."))
        t = t.trimmingCharacters(in: edges)
        t = t.replacingOccurrences(of: #"^(что|чтобы)\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
        t = t.trimmingCharacters(in: edges)
        return t.prefix(1).uppercased() + t.dropFirst()
    }
}
