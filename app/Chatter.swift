import AppKit
import IOKit.ps

/// О чём питомец болтает: малоизвестные сочетания клавиш macOS, фразы по времени суток и просто так.
enum Lines {
    struct Tip {
        let keys: String
        let text: String
    }

    static let tips: [Tip] = [
        Tip(keys: "⌥⌘V", text: "в Finder после ⌘C — переместить файл, а не скопировать"),
        Tip(keys: "⇧⌘.", text: "в Finder и окнах «Открыть» — показать скрытые файлы"),
        Tip(keys: "⇧⌘G", text: "в Finder и окнах «Открыть» — перейти к папке, вписав путь"),
        Tip(keys: "⌥⌘C", text: "в Finder — скопировать путь к выделенному файлу"),
        Tip(keys: "⌃⌘N", text: "в Finder — новая папка сразу с выделенными файлами внутри"),
        Tip(keys: "⌥ + клик по треугольнику", text: "в Finder в виде списка — раскрыть папку со всеми вложенными"),
        Tip(keys: "⌥Пробел", text: "в Finder — быстрый просмотр сразу на весь экран"),
        Tip(keys: "⌥⌘I", text: "в Finder — «живое» окно свойств, которое меняется вслед за выделением"),
        Tip(keys: "⌘ + клик по заголовку окна", text: "показать, в какой папке лежит открытый документ"),
        Tip(keys: "⌘ + перетаскивание", text: "двигать окно на заднем плане, не вытаскивая его вперёд"),
        Tip(keys: "⌘ + перетаскивание иконки в строке меню", text: "переставить её или убрать совсем"),
        Tip(keys: "⌥ + клик по Wi‑Fi", text: "в строке меню — IP-адрес, канал и качество сигнала"),
        Tip(keys: "⌥⇧ + громкость или яркость", text: "менять мелкими шагами, по четверть деления"),
        Tip(keys: "⌘Tab, затем ↓", text: "показать все окна выбранного приложения"),
        Tip(keys: "⌘Tab, затем Q", text: "не отпуская ⌘ — закрыть приложение прямо из переключателя"),
        Tip(keys: "⌘`", text: "переключаться между окнами одного приложения"),
        Tip(keys: "⌥⌘H", text: "спрятать все приложения, кроме текущего"),
        Tip(keys: "⌥⌘ + клик по иконке в Доке", text: "открыть приложение и спрятать все остальные"),
        Tip(keys: "⌥⌘W", text: "закрыть все окна приложения разом"),
        Tip(keys: "⌥⌘D", text: "спрятать или показать Док"),
        Tip(keys: "⌃⌘Q", text: "мгновенно заблокировать экран"),
        Tip(keys: "⌃⇧⌘4", text: "скриншот области сразу в буфер обмена, без файла на рабочем столе"),
        Tip(keys: "⇧⌘4, затем Пробел", text: "скриншот окна; с зажатой ⌥ при клике — без тени"),
        Tip(keys: "⌃⌘Пробел", text: "эмодзи и спецсимволы в любом поле ввода"),
        Tip(keys: "⌃⌘D", text: "словарь для слова под курсором"),
        Tip(keys: "⇧⌘/", text: "поиск по всем пунктам меню текущего приложения"),
        Tip(keys: "⌥⇧⌘V", text: "вставить текст без форматирования"),
        Tip(keys: "⌥⌫", text: "стереть слово целиком; ⌘⌫ — до начала строки"),
        Tip(keys: "⌃K, потом ⌃Y", text: "вырезать до конца строки и вставить обратно — свой мини-буфер в текстовых полях"),
        Tip(keys: "⌃T", text: "поменять местами две буквы возле курсора — лечит опечатки"),
        Tip(keys: "⌃A и ⌃E", text: "в начало и конец строки почти в любом текстовом поле"),
        Tip(keys: "⌥ в открытом меню", text: "показывает скрытые пункты, например «Сохранить как…»"),
        Tip(keys: "⌥⇧⌘Esc", text: "подержать 3 секунды — принудительно закрыть зависшее приложение"),
        Tip(keys: "⌘↩ в Spotlight", text: "показать найденный файл в Finder, а не открывать"),
        Tip(keys: "⇧⌘T", text: "в браузере — вернуть только что закрытую вкладку"),
        Tip(keys: "⌘L", text: "в браузере — сразу в адресную строку"),
    ]

    /// Что умеет сам питомец: lead выделяется, text — продолжение фразы.
    struct Skill {
        enum Needs { case nothing, cutout }
        let lead: String
        let text: String
        var needs = Needs.nothing
    }

    static let skills: [Skill] = [
        Skill(lead: "Двойной клик", text: " по мне — запишу напоминание. Можно прямо словами: «через 20 минут чайник»"),
        Skill(lead: "Брось в меня файл", text: " — подержу его в зубах, а когда понадобится, просто вытащи мышкой"),
        Skill(lead: "Правый клик", text: " по мне, когда держу файл, — переведу его в JPEG, PNG, PDF, MP4 или EPUB"),
        Skill(lead: "Скриншот или скан?", text: " Брось в меня и выбери «Достать текст» — скопирую весь текст с картинки"),
        Skill(lead: "Фото без фона?", text: " Брось его в меня и выбери «Убрать фон» — вырежу всё лишнее", needs: .cutout),
        Skill(lead: "Тяжёлый файл?", text: " Брось в меня и выбери «Сжать для отправки» — уменьшу картинку, PDF или видео"),
        Skill(lead: "Погладь меня", text: " — поводи курсором туда-сюда прямо надо мной"),
        Skill(lead: "Возьми меня мышкой", text: " и поставь на любое окно — буду гулять по нему и кататься вместе с ним"),
        Skill(lead: "Подержи курсор у моих лап", text: " — попробую поймать"),
        Skill(lead: "Отойдёшь от компьютера", text: " — я посплю, а вернёшься — встречу"),
        Skill(lead: "Батарея садится?", text: " На 15% я напомню про зарядку"),
        Skill(lead: "Один клик", text: " по мне — подпрыгну, а если сижу на стене — спрыгну"),
        Skill(lead: "«Поиграть в мячик»", text: " в меню — схвати мячик курсором и кинь, а я поймаю и принесу"),
        Skill(lead: "Швырни меня", text: " мышкой в край экрана — свернусь клубочком и отпружиню"),
        Skill(lead: "Меню «Напоминания»", text: " — там все будущие напоминания, оттуда же их можно удалить"),
    ]

    static func greeting(at hour: Int, on date: Date = Date()) -> String {
        let weekday = Calendar.current.component(.weekday, from: date)
        if (5..<12).contains(hour) && weekday == 2 && Bool.random() { return "Доброе утро понедельника! Начнём потихоньку" }
        if weekday == 6 && Bool.random() { return "Пятница! Привет-привет 🎉" }
        let lines: [String] = switch hour {
        case 5..<12: ["Доброе утро! Я рядом, если что 🐾", "Утречко! Как спалось?", "Доброе утро! Сегодня будет хороший день ☀️"]
        case 12..<18: ["Привет! Работаем?", "Привет-привет! Я соскучился", "О, привет! Что делаем сегодня?"]
        case 18..<23: ["Добрый вечер! Не засиживайся", "Вечер добрый! Составлю компанию", "Привет! Только недолго, ладно? Вечер же"]
        default: ["Ночь на дворе… ну ладно, я с тобой", "Не спится? Я тоже посижу", "Тсс… ночь. Работаем тихонько 🌙"]
        }
        return lines.randomElement()!
    }

    static func welcomeBack(_ species: Species) -> String {
        (species == .cat
            ? ["Мрр… я не спал, честно", "О, ты тут! Я чуть-чуть вздремнул", "Мяу! С возвращением", "Я грел тебе место 🐾",
               "Наконец-то! Я скучал"]
            : ["Гав! С возвращением!", "Ура, ты тут! Я ждал", "Я не спал, я охранял", "Ура-ура! Наконец-то!",
               "Я так скучал! Ну, минут пять"]).randomElement()!
    }

    static func purr(_ species: Species) -> String {
        (species == .cat
            ? ["Мррр…", "Мур-мур-мур", "Ещё, пожалуйста", "Вот тут ещё, за ушком", "Мрр, хорошо-то как", "Ты лучше всех гладишь"]
            : ["Ещё! Ещё!", "Ты самый лучший человек!", "Ух, как приятно", "Хвост сам виляет!", "А пузико почешешь?",
               "Счастье — это вот это"]).randomElement()!
    }

    /// Болтовня: забота, нежности, свои кошачьи или собачьи дела, а ещё — по времени суток, дню недели и сезону.
    static func macWake(_ species: Species) -> String {
        (species == .cat ? ["Мрр… мы проснулись? Доброе!", "Потягушки! Снова работаем?", "Мяу! Долго же мы спали"]
            : ["Гав! Проснулись! Ура!", "Потягушки! Снова работаем?", "Я тоже поспал. Отлично себя чувствую!"]).randomElement()!
    }

    static func phrase(_ species: Species, hour: Int, weather: Weather.Now? = nil, on date: Date = Date()) -> String {
        var lines = [
            "Попей воды, это полезно 💧",
            "Может, встанешь и потянешься?",
            "Глаза устали? Посмотри вдаль секунд двадцать",
            "Не забудь поморгать 👀",
            "Плечи опусти, выдохни. Вот так лучше",
            "Ты отлично справляешься",
            "Ты сегодня молодец. Да-да, именно ты",
            "Сделай паузу, мир подождёт",
            "Давай чуть-чуть передохнём? Совсем чуть-чуть",
            "Маленький шаг — тоже шаг",
            "Всё получится, я в тебя верю",
            "Если что — я за тебя болею",
            "Ошибки — это нормально. Даже я иногда падаю с окон",
            "Сегодня хороший день, чтобы быть добрым к себе",
            "Ты мне нравишься. Просто так",
            "Обнимашки на расстоянии 🤗",
            "Улыбнись — мне так спокойнее",
            "Я тут, рядышком 🐾",
            "Я слежу за курсором. Он хитрый",
            "Сколько вкладок… ты в порядке?",
            "Сохранился? ⌘S — лучший друг",
            "Тихо работаем, я не мешаю",
        ]
        lines += species == .cat
            ? ["Мур", "Мяу?", "Можно я полежу на клавиатуре?", "Погладь меня, пожалуйста", "Я бы сейчас поспал на солнышке ☀️",
               "Ловлю пылинки. Пока счёт 0:3", "Если что-то упадёт со стола — это не я", "Мурчу для продуктивности",
               "Коробки не найдётся? Просто спросил 📦", "Мяу. Это значит «ты классный человек»", "Хвост сегодня особенно пушистый"]
            : ["Гав!", "Пойдём гулять?", "Кто хороший человек? Ты!", "Я принёс тебе хорошее настроение 🦴",
               "Виляю хвостом — просто так, от радости", "Можно мне вкусняшку? Ну одну", "Я охраняю твой рабочий стол 🛡️",
               "Ты бросишь мячик? Я подожду", "Гав-гав! Это значит «люблю»", "Нюхаю новые файлы. Пахнут работой"]

        switch hour {
        case 6..<11: lines += ["Утро — время для чая ☕", "Позавтракать не забудь", "Потянемся? Утро же"]
        case 12..<15:
            lines += ["Обед по расписанию? 🍲", "Время перекусить"]
            lines.append(species == .cat ? "Я бы съел рыбки 🐟" : "Чем это пахнет? Обедом?")
        case 15..<18: lines += ["Самое время для перерыва на чай", "Ещё чуть-чуть — и вечер"]
        case 18..<23: lines += ["Вечер. Может, закругляемся?", "Сегодня сделано немало. Можно гордиться", "Скоро отдыхать 🌙"]
        default: lines += ["Уже поздно… может, пора спать?", "Завтра скажешь себе спасибо за сон", "Звёзды уже вышли ✨", "Я зеваю… и ты тоже?"]
        }

        let cal = Calendar.current
        switch cal.component(.weekday, from: date) {
        case 2: lines += ["Понедельник — это просто разминка", "С понедельничком! Держимся вместе"]
        case 6: lines += ["Пятница! Чувствуешь? 🎉", "Ещё немножко — и выходные"]
        case 1, 7: lines += ["Выходной же! Не перерабатывай", "В выходные можно и полениться"]
        default: break
        }

        let month = cal.component(.month, from: date), day = cal.component(.day, from: date)
        switch month {
        case 12, 1, 2: lines += ["Холодно… можно к тебе под плед? ❄️", "Пей тёплый чай, ладно?"]
        case 3...5: lines += ["Весна! Пахнет солнышком 🌷", "Слышишь? Птички"]
        case 6...8: lines += ["Жарко… водички? 🌞", "Лето! Окно открыть не хочешь?"]
        default: lines += ["Осень — время пледа и какао 🍂", "Листики шуршат… красиво"]
        }
        if month == 12 && day >= 20 { lines += ["Скоро Новый год! 🎄", "Пахнет мандаринками 🍊"] }
        if month == 1 && day <= 8 { lines.append("С Новым годом! Пусть он будет добрым ✨") }
        if month == 10 && day == 31 { lines.append("Бу! 🎃 Страшно? Мне тоже") }

        if let weather {
            let t = Int(weather.temperature.rounded())
            switch weather.kind {
            case .rain: lines += ["На улице дождь ☔ А у меня зонтик", "Пойдёшь гулять — возьми зонт", "Дождик стучит… уютно"]
            case .snow: lines += ["Снег идёт! ❄️ Хочу лепить снеговика", "За окном снежинки. Красота"]
            case .fog: lines.append("Туман за окном, как в сказке 🌫️")
            case .clear where (6..<20).contains(hour): lines.append("Солнышко на улице ☀️ Может, проветришь?")
            default: break
            }
            if t >= 25 { lines.append("На улице \(t)°, жара! Водички? 💧") }
            if t <= -5 { lines.append("На улице \(t)°… одевайся теплее 🧣") }
        }
        return lines.randomElement()!
    }
}

/// Когда и что говорить. Подсказки — сочетания клавиш и что умеет сам питомец — идут колодами:
/// пока не покажет все, не повторяется. Пока не рассказал о себе всё хотя бы раз, рассказывает чаще.
/// Следит за батареей: на 15% просит зарядку, на 5% — настойчиво, пока не заметят.
@MainActor
final class Chatter {
    private unowned let pet: Pet
    private let defaults = UserDefaults.standard
    private var nextAt = Date().addingTimeInterval(45)
    /// Сработавшие напоминания, которые ещё висят в пузыре; пока не прочитаны — подпрыгивает время от времени.
    private var due: [String] = []
    private var nextNudge = Date()
    /// Последний порог заряда, о котором уже сказал (100 — ни о каком).
    private var batteryWarned = 100
    private var nextBatteryCheck = Date()
    /// В пузыре висит предупреждение о батарее, а не напоминание.
    private var batteryBubble = false
    private var timer: Timer?
    /// Второй питомец: болтает по очереди с первым.
    weak var friend: Pet?
    /// Погода за окном — к болтовне добавляются фразы про неё.
    var weather: Weather.Now?
    var reminderSound = true
    var frequency: Double = 1 {
        didSet {
            if frequency != oldValue { nextAt = Date().addingTimeInterval(.random(in: 180...420) / frequency) }
        }
    }

    var enabled: Bool {
        didSet { defaults.set(enabled, forKey: "chatter") }
    }

    init(pet: Pet) {
        self.pet = pet
        enabled = defaults.object(forKey: "chatter") as? Bool ?? true
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func greet() {
        guard enabled else { return }
        pet.say(Self.plain(Lines.greeting(at: hour)))
    }

    func tipNow() {
        let tip = Lines.tips[draw(from: Array(Lines.tips.indices), key: "tipsShown")]
        say("💡 ", tip.keys, " — \(tip.text)")
    }

    /// Рассказать о своём умении.
    func skillNow() {
        let available = Lines.skills.indices.filter {
            switch Lines.skills[$0].needs {
            case .nothing: true
            case .cutout: Converter.canRemoveBackground
            }
        }
        let index = draw(from: available, key: "skillsShown")
        if Set(defaults.array(forKey: "skillsShown") as? [Int] ?? []).isSuperset(of: available) {
            defaults.set(true, forKey: "skillsAllSeen")
        }
        let skill = Lines.skills[index]
        say("🐾 ", skill.lead, skill.text)
    }

    /// Карта из колоды: ещё не показанная; когда показаны все — колода тасуется заново.
    private func draw(from deck: [Int], key: String) -> Int {
        var shown = Set(defaults.array(forKey: key) as? [Int] ?? []).intersection(deck)
        if shown.count >= deck.count { shown = [] }
        let index = deck.filter { !shown.contains($0) }.randomElement()!
        shown.insert(index)
        defaults.set(Array(shown), forKey: key)
        return index
    }

    private func say(_ prefix: String, _ lead: String, _ rest: String) {
        let text = NSMutableAttributedString(string: prefix, attributes: Self.body)
        text.append(NSAttributedString(string: lead, attributes: Self.keys))
        text.append(NSAttributedString(string: rest, attributes: Self.body))
        pet.say(text)
        nextAt = Date().addingTimeInterval(.random(in: 180...420) / frequency)
    }

    /// Напоминание говорится, даже если болтовня выключена, и висит до клика по пузырю.
    func remind(_ text: String) {
        if !pet.isReminding { due = [] }
        batteryBubble = false
        due.append(text)
        let s = NSMutableAttributedString(string: "⏰ Напоминаю:", attributes: Self.keys)
        for line in due {
            s.append(NSAttributedString(string: "\n" + line, attributes: Self.body))
        }
        pet.say(s, sticky: true)
        pet.callForAttention()
        if reminderSound { NSSound(named: "Glass")?.play() }
        nextNudge = Date().addingTimeInterval(20)
    }

    func welcomeBack() {
        guard enabled else { return }
        pet.say(Self.plain(Lines.welcomeBack(pet.species)))
    }

    /// Гладят — иногда мурлычет вслух. who — кого гладят, если не первого.
    func purr(_ who: Pet? = nil) {
        let speaker = who ?? pet
        guard enabled, !speaker.isSpeaking, Double.random(in: 0..<1) < 0.5 else { return }
        speaker.say(Self.plain(Lines.purr(speaker.species)))
    }

    func say(_ text: String) {
        pet.say(Self.plain(text))
    }

    private func check() {
        if Date() >= nextBatteryCheck {
            nextBatteryCheck = Date().addingTimeInterval(30)
            checkBattery()
        }
        if pet.isReminding {
            if Date() >= nextNudge {
                pet.callForAttention()
                nextNudge = Date().addingTimeInterval(20)
            }
            return
        }
        guard enabled, Date() >= nextAt, !pet.isSpeaking, !pet.isSleeping else { return }
        let roll = Double.random(in: 0..<1)
        let skills = defaults.bool(forKey: "skillsAllSeen") ? 0.15 : 0.5
        if roll < skills {
            skillNow()
        } else if roll < skills + (1 - skills) * 0.6 {
            tipNow()
        } else {
            let speaker = friend.flatMap { Bool.random() && !$0.isSpeaking && !$0.isSleeping ? $0 : nil } ?? pet
            speaker.say(Self.plain(Lines.phrase(speaker.species, hour: hour, weather: weather)))
            nextAt = Date().addingTimeInterval(.random(in: 180...420) / frequency)
        }
    }

    private var hour: Int { Calendar.current.component(.hour, from: Date()) }

    /// Говорит о батарее даже с выключенной болтовнёй: это не болтовня.
    private func checkBattery() {
        guard let battery = Self.battery() else { return }  // у настольных Маков батареи нет
        if battery.charging {
            if batteryBubble && pet.isReminding { pet.hideSpeech() }
            if batteryWarned <= 15 { pet.say(Self.plain("Ням, зарядка! 🔌")) }
            batteryWarned = 100
            batteryBubble = false
            return
        }
        if battery.percent <= 5 && batteryWarned > 5 {
            batteryWarned = 5
            pet.say(Self.plain("🪫 \(battery.percent)%! Срочно покорми ноутбук 🔌"), sticky: true)
            batteryBubble = true
            pet.callForAttention()
            nextNudge = Date().addingTimeInterval(20)
        } else if battery.percent <= 15 && batteryWarned > 15 {
            batteryWarned = 15
            pet.say(Self.plain("🔋 Осталось \(battery.percent)%. Покорми ноутбук 🔌"))
            pet.callForAttention()
        }
    }

    /// Заряд встроенной батареи и подключена ли зарядка.
    private static func battery() -> (percent: Int, charging: Bool)? {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return nil }
        for source in sources {
            guard let d = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  d[kIOPSTypeKey] as? String == kIOPSInternalBatteryType,
                  let current = d[kIOPSCurrentCapacityKey] as? Int, let max = d[kIOPSMaxCapacityKey] as? Int, max > 0
            else { continue }
            return (current * 100 / max, d[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue)
        }
        return nil
    }

    private static let body: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: SpeechBubble.ink,
    ]
    private static let keys: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 13, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 196 / 255, green: 92 / 255, blue: 36 / 255, alpha: 1),
    ]

    static func plain(_ text: String) -> NSAttributedString {
        NSAttributedString(string: text, attributes: body)
    }
}
