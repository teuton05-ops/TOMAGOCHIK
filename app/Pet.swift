import AppKit

enum Species: String, CaseIterable {
    case cat, dog

    var title: String { self == .cat ? "Котик" : "Собака" }
}

/// Кадры одной анимации, нарезанные из спрайт-листа (кадры квадратные, идут слева направо).
struct Animation {
    let frames: [CGImage]
    let frameDuration: TimeInterval

    init(_ name: String, frameDuration: TimeInterval) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "sprites"),
              let sheet = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
        else { fatalError("Нет спрайта \(name)") }
        let size = sheet.height
        frames = (0..<sheet.width / size).compactMap {
            sheet.cropping(to: CGRect(x: $0 * size, y: 0, width: size, height: size))
        }
        self.frameDuration = frameDuration
    }

    func frame(at time: TimeInterval) -> CGImage {
        frames[Int(time / frameDuration) % frames.count]
    }
}

/// Поведение питомца: гуляет по низу экрана и по верхним кромкам окон, запрыгивает на окна,
/// спрыгивает с них, катается вместе с окном, которое двигают. От клика подпрыгивает,
/// если его отпустить — падает на то, что окажется под лапами. Следит глазами за курсором
/// и иногда гоняется за ним, за шкирку висит и болтает лапами, после прыжка приседает.
/// Дойдя до бокового края экрана, может забраться по нему вверх. Когда человек отошёл — засыпает,
/// проснувшись — потягивается. Перед прыжком приседает, в полёте вытягивается, под ним тень.
/// В покое садится и умывается, бьёт лапкой курсор у самых лап, балансирует на краю,
/// цепляется за трясущееся окно, жмурится и пускает сердечки, когда гладят курсором.
/// Изредка ловит бабочку, пукает или делает свои дела и закапывает. Играет в мячик: ловит и приносит.
/// Если швырнуть его в край экрана, сворачивается клубком и отпружинивает.
/// Пританцовывает, когда играет музыка, позирует для скриншота. Вдвоём с другом играет в догонялки и обнимается.
/// В дождь ходит под зонтиком, ночью зевает и дремлет на подушке, после сна Мака потягивается,
/// бегает рыться в Корзину и сам иногда прячется — торчит только хвост, пока не найдут.
@MainActor
final class Pet {
    enum State { case idle, walking, held, airborne, climbing, sleeping }

    /// Логический размер — 48 точек; текстуры 128×128 нарезаются по высоте листа.
    /// scale меняет размер питомца на экране независимо от разрешения рисунка.
    static let spriteSize: CGFloat = 48
    /// Скорость ходьбы в пикселях спрайта в секунду: 2 px за кадр ходьбы, чтобы лапы не скользили.
    static let walkSpeed: CGFloat = 2 / 0.14
    static let gravity: CGFloat = 2600
    /// Во сколько раз бег за курсором быстрее шага; кадры ходьбы ускоряются так же.
    static let runFactor: CGFloat = 2.2
    /// Сколько секунд без мыши и клавиатуры, чтобы уснуть.
    static let sleepAfter: TimeInterval = 300

    let window: NSPanel
    let view: PetView
    var species: Species { didSet { view.clearAppearanceCache(); loadAnimations() } }
    var scale: CGFloat { didSet { resize() } }
    var movementSpeed: CGFloat = 1
    private var walkingSpeed: CGFloat { Pet.walkSpeed * movementSpeed }
    var sleepDelay: TimeInterval = Pet.sleepAfter
    var chasesCursor = true {
        didSet { if !chasesCursor { stopChasing() } }
    }
    var cornerSide = "right"
    var cornerOrder = 0
    var cornerMode = false {
        didSet {
            guard cornerMode != oldValue else { return }
            if cornerMode {
                pickUp() // Завершаем игры, прятки и перенос предметов.
                rest(for: 1)
                parkInCorner()
                window.setFrameOrigin(origin)
            } else if state != .held {
                rest(for: 1)
            }
        }
    }

    private var idle: Animation!
    private var walk: Animation!
    /// 9 направлений взгляда × 2 взмаха хвоста.
    private var look: Animation!
    private var hang: Animation!
    /// Глубокий и неглубокий присед.
    private var crouch: Animation!
    private var sleep: Animation!
    private var sit: Animation!
    /// Котик умывается, собака чешется.
    private var groom: Animation!
    /// Потягивание и зевок.
    private var wakeUp: Animation!
    private var swipe: Animation!
    private var balance: Animation!
    private var happy: Animation!
    /// Присел по делам (0, 1) и закапывает (2, 3).
    private var potty: Animation!
    private var curl: Animation!
    private var dance: Animation!
    /// Сидит, подмигивает и машет лапкой.
    private var pose: Animation!
    private var photoPose = PhotoPose()

    /// Разовое действие на месте: кадры по очереди, в конце — then. Пока идёт, питомец стоит.
    private struct Act {
        var frames: [(image: CGImage, duration: TimeInterval)]
        var start = Date()
        /// Покачивается вокруг лап: скорость (рад/с) и размах (рад) — балансирует, танцует.
        var sway: (speed: Double, amount: CGFloat)?
        /// Над головой вылетают нотки.
        var notes = false
        /// Можно перебить поглаживанием: сидит, умывается. Прыжок и шаг с края — нельзя.
        var calm = false
        var then: (() -> Void)?

        var end: Date { start.addingTimeInterval(frames.reduce(0) { $0 + $1.duration }) }

        func frame(at now: Date) -> CGImage {
            var t = now.timeIntervalSince(start)
            for f in frames {
                if t < f.duration { return f.image }
                t -= f.duration
            }
            return frames[frames.count - 1].image
        }
    }
    private var act: Act?
    private var state = State.idle
    private var stateUntil = Date()
    private var stateTime: TimeInterval = 0
    private var direction: CGFloat = 1
    private var velocity = CGVector.zero
    /// Левый нижний угол окна питомца = точка, где стоят лапы (по y).
    private var origin = NSPoint.zero
    private var lastTick = Date()
    private var timer: Timer?
    /// Решили шагнуть с края: идём, пока лапы не окажутся в воздухе.
    private var walkingOff = false
    /// Питомца поставили руками: после приземления он какое-то время не уходит со своей кромки.
    private var placedByUser = false
    private var stayUntil = Date.distantPast
    private var staying: Bool { Date() < stayUntil }
    /// Полоска на кромке, куда встанет питомец, пока его тащат.
    private let hint: NSPanel
    private let bubble = SpeechBubble()
    private let dust = Dust()
    private let shadow = Shadow()
    private let emotes = Emotes()
    /// Мячик общий на двоих: кто держит его в зубах, тот ball.carrier.
    let ball: Ball
    private let butterfly = Butterfly()
    private var butterflySince = Date()
    private var butterflyWatchUntil = Date.distantFuture
    private var butterflyJumped = false
    /// Поймал бабочку в прыжке — после приземления радуется.
    private var proudAfterLanding = false
    private let poop = Prop()
    private var poopAt: NSPoint?
    private var poopSince = Date()
    private var buryStart: Date?
    private var nextDirt = Date()
    /// Следующее редкое событие — не раньше.
    private var nextRare = Date().addingTimeInterval(.random(in: 180...360))
    /// Куда смотрит вместо курсора: на мячик, на бабочку.
    private var lookAt: NSPoint?
    /// Мячик: до каких пор несёт его в зубах, когда снова можно ловить и прыгать за ним.
    private var ballCarryUntil = Date.distantPast
    private var ignoreBallUntil = Date.distantPast
    private var nextBallJump = Date.distantPast
    /// Бежит за мячиком в этом кадре — быстрые кадры, как в погоне.
    private var running = false
    /// Брошен в стену: летит клубком и крутится.
    private var curled = false
    private var spin: CGFloat = 0
    /// Музыка играет — время от времени пританцовывает.
    var musicPlaying = false {
        didSet { if musicPlaying && !oldValue { nextDance = Date() } }
    }
    private var nextDance = Date.distantFuture
    private var nextNote = Date()
    /// Второй питомец рядом: догонялки и обнимашки.
    weak var friend: Pet?
    private enum Game { case chaser, runner, visitor }
    private var game: Game?
    private var gameUntil = Date()
    private var gameSwapAt = Date()
    private var nextFriendPlay = Date().addingTimeInterval(.random(in: 20...60))
    /// Принимает ли брошенные файлы: у второго питомца зубы для мячика.
    var acceptsFiles = true
    /// Сказать от себя: нашёл что-то в Корзине, прятки.
    var onSay: ((String) -> Void)?

    /// Погода за окном: в дождь — зонтик, в снег — снежинки вокруг.
    var weather: Weather.Kind?
    private let weatherFX = WeatherFX()
    /// Ночью дремлет на подушке до napUntil, даже если человек рядом.
    private let pillow = Prop()
    private var napUntil: Date?
    private var isNight: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 23 || hour < 6
    }
    /// Бежит к Корзине в Доке (x на полу), потом роется и показывает находку.
    private var trashTrip: CGFloat?
    private let trinket = Prop()
    private var trinketArt: PixelArt?
    private var trinketCarried = false
    private var trinketDrop: (position: NSPoint, vy: CGFloat, since: Date)?
    /// Прятки: куда бежит, куда смотрит, за каким окном прячется, до каких пор сидит (nil — ещё бежит).
    private struct Hide {
        var x: CGFloat
        var facing: CGFloat
        var behind: CGWindowID?
        var frame: CGRect?
        var until: Date?
    }
    private var hide: Hide?
    var isSpeaking: Bool { bubble.isVisible }
    /// Двойной клик: новое напоминание.
    var onDoubleClick: (() -> Void)?
    /// Проснулся, потому что человек вернулся.
    var onWake: (() -> Void)?
    /// Начали гладить.
    var onPetted: (() -> Void)?
    var isSleeping: Bool { state == .sleeping }

    /// Что держит в зубах. Файлы остаются на своих местах, питомец хранит только ссылки на них.
    var held: [URL] = [] {
        didSet {
            view.held = held
            onHeldChange?(held)
        }
    }
    var onHeldChange: (([URL]) -> Void)?

    /// Прыгать ли по блокам внутри переднего окна (нужен доступ «Универсальный доступ»).
    var blocksEnabled = false
    private let blockScanner = BlockScanner()
    private var world = World()
    private var lastScan = Date.distantPast
    /// На чём стоим: окно (0 — пол экрана) и его рамка на прошлом шаге, чтобы ехать вместе с ним.
    private var supportID: CGWindowID = 0
    private var supportFrame: CGRect?

    /// Курсор: где он, когда двигался и как быстро (сглаженно, точек в секунду).
    private var mouse = NSEvent.mouseLocation
    private var mouseMovedAt = Date.distantPast
    private var mouseSpeed: CGFloat = 0
    private var lastTurn = Date.distantPast
    private var chasing = false
    private var chaseUntil = Date()
    private var nextChase = Date().addingTimeInterval(5)
    /// Присед после приземления.
    private var landedAt = Date.distantPast
    private var hardLanding = false
    /// Маятник за шкирку: угол (радианы), его скорость и сглаженная скорость руки.
    private var swing: CGFloat = 0
    private var swingSpeed: CGFloat = 0
    private var handSpeed: CGFloat = 0
    private var handX: CGFloat = 0
    private var handVY: CGFloat = 0
    private var handY: CGFloat = 0
    /// Стена, по которой лезет: +1 правая, −1 левая; её x и докуда можно лезть.
    private var wallSide: CGFloat = 1
    private var wallX: CGFloat = 0
    private var wallFloor: CGFloat = 0
    private var wallTop: CGFloat = 0
    /// +1 вверх, −1 вниз, 0 — висит и думает до climbPauseUntil.
    private var climbDir: CGFloat = 1
    private var climbHeadDown = false
    private var climbTarget: CGFloat = 0
    private var climbPauseUntil = Date.distantPast
    /// Открыта форма напоминания: стоит на месте и смотрит на курсор.
    private var paused = false
    /// Поглаживание: смены направления курсора над питомцем за последние полторы секунды.
    private var strokeDir: CGFloat = 0
    private var strokes: [Date] = []
    private var pettedUntil = Date.distantPast
    private var nextHeart = Date.distantPast
    private var nextPurr = Date.distantPast
    private var nextSwipe = Date.distantPast
    /// Скорость окна, на котором стоит (сглаженная), и до каких пор держится за него.
    private var windowVelocity = CGVector.zero
    private var clingUntil = Date.distantPast

    var size: CGFloat { Pet.spriteSize * scale }
    /// Клетка разметки — 1/32 питомца: в ней заданы скорости, прыжки и все эффекты вокруг.
    private var px: CGFloat { size / 32 }
    private var unit: CGFloat { px / 3 }  // дальности прыжков подобраны для среднего размера
    private var centerX: CGFloat { origin.x + size / 2 }

    init(species: Species, scale: CGFloat, ball: Ball, x: CGFloat? = nil) {
        self.species = species
        self.scale = scale
        self.ball = ball
        view = PetView(frame: .zero)
        window = Pet.overlay()
        window.contentView = view
        hint = Pet.overlay()
        hint.ignoresMouseEvents = true
        hint.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.8)
        view.pet = self
        loadAnimations()
        resize()

        let area = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        origin = NSPoint(x: x ?? area.midX - size / 2, y: area.minY)
        window.setFrameOrigin(origin)
        window.orderFrontRegardless()
        rest(for: 1.5)

        let timer = Timer(timeInterval: 1 / 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    /// Убрать насовсем: второго питомца отпустили.
    func dismiss() {
        timer?.invalidate()
        timer = nil
        if ball.carrier === self { ball.carrier = nil }
        if game != nil { endGame() }
        friend?.friend = nil
        friend = nil
        butterfly.remove()
        poop.hide()
        pillow.hide()
        trinket.hide()
        weatherFX.hide()
        bubble.hide()
        shadow.hide()
        emotes.hide()
        hint.orderOut(nil)
        window.orderOut(nil)
    }

    /// Прозрачная панель поверх всех окон. Не забирает фокус: браузер остаётся передним окном,
    /// и сканер блоков продолжает видеть его, даже пока питомца тащат.
    static func overlay() -> NSPanel {
        let panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        return panel
    }

    // MARK: - Реакции на мышь

    /// Клик: на стене — спрыгивает, спящий — просыпается, на ногах — радостно подпрыгивает.
    func poke() {
        if cornerMode { onPetted?(); return }
        if hide?.until != nil {
            comeOut(found: true)
            return
        }
        switch state {
        case .climbing: leaveWall()
        case .sleeping: wake(greet: true)
        case .idle, .walking: hop(CGVector(dx: 0, dy: 600 * unit))
        default: break
        }
    }

    func doubleClick() {
        if hide?.until != nil {
            comeOut(found: true)
            return
        }
        if state == .sleeping { wake(greet: false) }
        if state == .idle || state == .walking { onDoubleClick?() }
    }

    /// Подождать на месте, пока открыто меню или форма.
    func pause(_ on: Bool) {
        guard on != paused else { return }
        paused = on
        if on {
            stopChasing()
            if !isReminding { bubble.hide() }
        } else if state == .idle {
            rest(for: .random(in: 1...2))
        }
    }

    /// Подпрыгнуть, чтобы заметили.
    func callForAttention() {
        if state == .sleeping { wake(greet: false) }
        if state == .idle || state == .walking { hop(CGVector(dx: 0, dy: 700 * unit)) }
    }

    // MARK: - Реплики и файлы в зубах

    var isReminding: Bool { bubble.isVisible && bubble.isSticky }

    func hideSpeech() {
        bubble.hide()
    }

    /// Липкую реплику (напоминание) обычная болтовня не перебивает.
    func say(_ text: NSAttributedString, sticky: Bool = false) {
        guard sticky || !isReminding else { return }
        bubble.show(text, sticky: sticky)
        followBubble()
    }

    /// Над питомцем тащат файл: остановиться и подождать.
    func noticeIncomingFile() {
        guard state == .idle || state == .walking else { return }
        stopChasing()
        rest(for: 4)
    }

    func hold(_ urls: [URL]) {
        held += urls.filter { !held.contains($0) }
        if state == .idle || state == .walking { hop(CGVector(dx: 0, dy: 500 * unit)) }  // радостный подскок
        Pet.requestAccess(to: urls)
    }

    /// «Загрузки», «Документы» и «Рабочий стол» защищены: без доступа к ним macOS молча выкидывает файл
    /// из перетаскивания, и отдать его не выйдет. Пробуем прочитать — система один раз спросит разрешение.
    /// В фоне: пока человек думает над запросом, вызов ждёт ответа.
    static func requestAccess(to urls: [URL]) {
        DispatchQueue.global(qos: .utility).async {
            for url in urls {
                if url.hasDirectoryPath {
                    _ = try? FileManager.default.contentsOfDirectory(atPath: url.path)
                } else {
                    try? FileHandle(forReadingFrom: url).close()
                }
            }
        }
    }

    func letGo() {
        held = []
    }

    var head: NSPoint { NSPoint(x: origin.x + size * (direction < 0 ? 0.3 : 0.7), y: origin.y + size * 0.78) }

    var screenArea: NSRect {
        let screen = NSScreen.screens.first { $0.frame.contains(NSPoint(x: centerX, y: origin.y + 1)) } ?? NSScreen.main
        return screen?.visibleFrame ?? .zero
    }

    private func followBubble() {
        bubble.follow(head: head, within: screenArea)
    }

    func pickUp() {
        stopChasing()
        act = nil
        state = .held
        stateTime = 0
        placedByUser = false
        stayUntil = .distantPast
        swing = 0
        swingSpeed = 0
        handSpeed = 0
        handX = origin.x
        handVY = 0
        handY = origin.y
        if ball.carrier === self {
            ball.carrier = nil  // выронил
            ball.velocity = .zero
        }
        if game != nil { endGame() }
        if trinketCarried { dropTrinket() }
        trashTrip = nil
        napUntil = nil
        if hide != nil {
            hide = nil
            window.level = .floating
        }
    }

    func drag(to point: NSPoint) {
        origin = point
        window.setFrameOrigin(origin)
        showHint(dropTarget())
    }

    func drop() {
        showHint(nil)
        // Швырнули — летит со скоростью руки
        let speed = hypot(handSpeed, handVY)
        if speed > 500 {
            let k = min(1, 4000 * unit / speed)
            launch(CGVector(dx: handSpeed * k, dy: handVY * k))
            return
        }
        placedByUser = true
        if let target = dropTarget(), target.y >= origin.y - 1 {
            land(on: target)  // лапы чуть залезли в блок — ставим на его кромку
            window.setFrameOrigin(origin)
        } else {
            launch(.zero)
        }
    }

    /// Куда встанет питомец, если отпустить: ближайшая кромка под лапами
    /// или чуть выше них, если лапы уже залезли в блок.
    private func dropTarget() -> Platform? {
        world.platforms
            .filter { $0.holds(centerX) && $0.y <= origin.y + size * 0.35 }
            .max { $0.y < $1.y }
    }

    private func showHint(_ target: Platform?) {
        guard let target else {
            hint.orderOut(nil)
            return
        }
        hint.setFrame(NSRect(x: target.x0, y: target.y - 2, width: target.width, height: 4), display: true)
        hint.orderFrontRegardless()
    }

    // MARK: - Состояния

    private func loadAnimations() {
        idle = Animation("\(species.rawValue)_idle", frameDuration: 0.3)
        walk = Animation("\(species.rawValue)_walk", frameDuration: 0.14)
        look = Animation("\(species.rawValue)_look", frameDuration: 0.3)
        hang = Animation("\(species.rawValue)_hang", frameDuration: 0.12)
        crouch = Animation("\(species.rawValue)_land", frameDuration: 0.1)
        potty = Animation("\(species.rawValue)_potty", frameDuration: 0.12)
        curl = Animation("\(species.rawValue)_curl", frameDuration: 1)
        dance = Animation("\(species.rawValue)_dance", frameDuration: 0.18)
        pose = Animation("\(species.rawValue)_pose", frameDuration: 0.25)
        sleep = Animation("\(species.rawValue)_sleep", frameDuration: 0.6)
        sit = Animation("\(species.rawValue)_sit", frameDuration: 0.3)
        groom = Animation("\(species.rawValue)_groom", frameDuration: species == .cat ? 0.2 : 0.12)
        wakeUp = Animation("\(species.rawValue)_stretch", frameDuration: 0.5)
        swipe = Animation("\(species.rawValue)_swipe", frameDuration: 0.12)
        balance = Animation("\(species.rawValue)_balance", frameDuration: 0.15)
        happy = Animation("\(species.rawValue)_happy", frameDuration: species == .cat ? 0.25 : 0.09)
    }

    private func resize() {
        window.setContentSize(NSSize(width: size, height: size))
        view.frame = NSRect(x: 0, y: 0, width: size, height: size)
    }

    private func rest(for seconds: TimeInterval) {
        act = nil
        walkingOff = false
        state = .idle
        stateTime = 0
        stateUntil = Date().addingTimeInterval(seconds)
    }

    private func stroll(_ dir: CGFloat? = nil) {
        act = nil
        walkingOff = false
        state = .walking
        stateTime = 0
        direction = dir ?? (Bool.random() ? 1 : -1)
        stateUntil = Date().addingTimeInterval(.random(in: 3...9))
    }

    private func launch(_ v: CGVector) {
        stopChasing()
        act = nil
        curled = false
        napUntil = nil
        walkingOff = false
        state = .airborne
        stateTime = 0
        velocity = v
        if v.dx != 0 { direction = v.dx > 0 ? 1 : -1 }
    }

    /// impact — скорость падения в момент касания: от неё зависят глубина приседа и пыль.
    private func land(on p: Platform, impact: CGFloat = 0) {
        origin.y = p.y
        supportID = p.windowID
        supportFrame = world.windowFrames[p.windowID]
        landedAt = Date()
        hardLanding = impact > 800 * unit || curled
        if impact > 600 * unit || curled {
            dust.puff(at: NSPoint(x: centerX, y: origin.y), pixel: px, strength: impact / (1800 * unit), below: window)
        }
        curled = false
        spin = 0
        if placedByUser {
            placedByUser = false
            stayUntil = Date().addingTimeInterval(.random(in: 20...40))
            rest(for: .random(in: 2...4))
        } else {
            rest(for: .random(in: 0.8...2.5))
        }
        if proudAfterLanding {
            proudAfterLanding = false
            perform(Act(frames: looped(happy, for: 1.5), calm: true) { [unowned self] in rest(for: 1) })
        }
    }

    // MARK: - Разовые действия

    private func perform(_ act: Act) {
        stopChasing()
        walkingOff = false
        state = .idle
        stateTime = 0
        self.act = act
    }

    /// Кадры анимации по кругу примерно на seconds секунд.
    private func looped(_ anim: Animation, for seconds: TimeInterval) -> [(image: CGImage, duration: TimeInterval)] {
        let count = max(anim.frames.count, Int(seconds / anim.frameDuration))
        return (0..<count).map { (anim.frames[$0 % anim.frames.count], anim.frameDuration) }
    }

    /// Прыжок с подготовкой: сначала приседает, потом отталкивается.
    private func hop(_ v: CGVector) {
        if v.dx != 0 { direction = v.dx > 0 ? 1 : -1 }
        perform(Act(frames: [(crouch.frames[1], 0.05), (crouch.frames[0], 0.09)]) { [unowned self] in launch(v) })
    }

    /// Постоял — иногда садится или умывается (собака чешется).
    private func fidget() -> Bool {
        switch Double.random(in: 0..<1) {
        case ..<0.18:
            perform(Act(frames: looped(sit, for: .random(in: 3...7)), calm: true) { [unowned self] in rest(for: .random(in: 0.3...1)) })
        case ..<0.3:
            perform(Act(frames: looped(groom, for: .random(in: 1.5...3)), calm: true) { [unowned self] in rest(for: .random(in: 0.5...1.5)) })
        default:
            return false
        }
        return true
    }

    /// Шаги подряд: у каждого свои кадры и что сделать в его начале; в конце — постоять.
    private func sequence(_ steps: [(frames: [(image: CGImage, duration: TimeInterval)], start: (() -> Void)?)]) {
        guard let first = steps.first else {
            rest(for: .random(in: 0.5...1.5))
            return
        }
        first.start?()
        perform(Act(frames: first.frames) { [unowned self] in sequence(Array(steps.dropFirst())) })
    }

    // MARK: - Редкие события

    /// Раз в несколько минут: ловит бабочку, пукает или делает свои дела.
    private func rareEvent() -> Bool {
        guard Date() >= nextRare, !ball.isActive, !staying, Double.random(in: 0..<1) < 0.12 else { return false }
        nextRare = Date().addingTimeInterval(.random(in: 240...600))
        switch Int.random(in: 0..<5) {
        case 0: startButterfly()
        case 1: fart()
        case 2: poopAndBury()
        case 3: if let p = support(), startHide(on: p) {} else { fart() }
        default: goToTrash()
        }
        return true
    }

    private func startButterfly() {
        let area = screenArea
        let fromLeft = Bool.random()
        butterfly.pixel = px
        butterfly.spawn(from: NSPoint(x: fromLeft ? area.minX - 20 : area.maxX + 20, y: origin.y + size * .random(in: 2...3.5)),
                        toward: NSPoint(x: centerX + .random(in: -size...size), y: origin.y + size * 1.9))
        butterflySince = Date()
        butterflyWatchUntil = .distantFuture
        butterflyJumped = false
        rest(for: 1)
    }

    /// Бабочка прилетела: смотрит на неё, повисела рядом — прыгает ловить.
    private func watchButterfly(_ now: Date) {
        lookAt = butterfly.position
        if state != .idle {
            state = .idle
            stateTime = 0
        }
        faceMouse(now)
        if now.timeIntervalSince(butterflySince) > 25 { butterfly.flyAway() }  // так и не поймал
        let d = hypot(butterfly.position.x - centerX, butterfly.position.y - origin.y - size * 1.9)
        if d < size && butterflyWatchUntil == .distantFuture {
            butterflyWatchUntil = now.addingTimeInterval(.random(in: 1...2.5))
        }
        guard now >= butterflyWatchUntil, !butterflyJumped else { return }
        butterflyJumped = true
        let height = max(butterfly.position.y - origin.y - size * 0.5, size * 0.5)
        hop(CGVector(dx: (butterfly.position.x - centerX) * 1.5, dy: sqrt(2 * Pet.gravity * unit * height)))
    }

    /// В верхней точке прыжка: поймал или упустил.
    private func reachForButterfly() {
        guard butterflyJumped, butterfly.isActive, butterfly.target != nil, velocity.dy <= 0 else { return }
        if hypot(butterfly.position.x - mouth.x, butterfly.position.y - mouth.y) < size * 1.2 && Bool.random() {
            butterfly.remove()
            emotes.show(.heart)
            proudAfterLanding = true
        } else {
            butterfly.flyAway()
            emotes.show(.puzzled)
        }
    }

    /// Зажмурился, пукнул, оглянулся на облачко, смущённо отвернулся.
    private func fart() {
        sequence([
            ([(idle.frames[2], 0.6)], nil),
            ([(idle.frames[0], 0.4)], { [unowned self] in
                dust.puff(at: NSPoint(x: centerX - direction * size * 0.4, y: origin.y + size * 0.25), pixel: px,
                          strength: 0.6, below: window, color: DustView.fart, side: -direction)
            }),
            ([(look.frames[8], 1.1)], { [unowned self] in
                direction = -direction
                emotes.show(.puzzled)
            }),
            (looped(happy, for: 0.8), { [unowned self] in direction = -direction }),
        ])
    }

    /// Присел, тужится, оставил кучку, развернулся и закопал её.
    private func poopAndBury() {
        let squat = (0..<5).map { (potty.frames[$0 % 2], 0.25) }
        let dig = (0..<14).map { (potty.frames[2 + $0 % 2], 0.13) }
        sequence([
            (squat, nil),
            ([(idle.frames[0], 0.5)], { [unowned self] in
                poopAt = NSPoint(x: centerX - direction * size * 0.55, y: origin.y + px * 2)
                poopSince = Date()
                buryStart = nil
            }),
            ([(look.frames[8], 0.6)], { [unowned self] in direction = -direction }),
            (dig, { [unowned self] in buryStart = Date() }),
            (looped(happy, for: 1), { [unowned self] in
                direction = -direction
                poopAt = nil
            }),
        ])
    }

    /// Кучка: пока закапывает — бледнеет и летят комья земли; если отвлекли — тает сама.
    private func updatePoop(_ now: Date) {
        guard let at = poopAt else {
            poop.hide()
            return
        }
        var alpha: CGFloat = 1
        if let buryStart {
            alpha = max(0, 1 - CGFloat(now.timeIntervalSince(buryStart) / 1.8))
            if now >= nextDirt {
                nextDirt = now.addingTimeInterval(0.3)
                dust.puff(at: NSPoint(x: centerX + direction * size * 0.25, y: origin.y), pixel: px, strength: 0.2,
                          below: window, color: DustView.dirt, side: direction)
            }
        } else if now.timeIntervalSince(poopSince) > 8 {
            alpha = max(0, 1 - CGFloat(now.timeIntervalSince(poopSince) - 8))
        }
        if alpha <= 0 {
            poopAt = nil
            poop.hide()
        } else {
            poop.show(Arts.poop, center: at, pixel: px, alpha: alpha)
        }
    }

    // MARK: - Мячик

    var hasBall: Bool { ball.isActive }

    func toggleBall() {
        if ball.isActive {
            ball.remove()
        } else {
            ball.pixel = px
            ball.spawn(at: NSPoint(x: centerX + direction * size, y: origin.y + size * 2))
        }
    }

    /// Где рот: туда прилетает мячик и там его носят.
    private var mouth: NSPoint {
        NSPoint(x: origin.x + size * (direction > 0 ? 0.72 : 0.28), y: origin.y + size * 0.38)
    }

    private func catchBallIfClose(_ now: Date) {
        guard !cornerMode else { return }
        guard ball.isActive, !ball.isGrabbed, ball.carrier == nil, now >= ignoreBallUntil,
              now.timeIntervalSince(ball.touchedAt) < 25,  // наигрался — мимо лежащего мячика проходит
              [.idle, .walking, .airborne].contains(state),
              hypot(ball.position.x - mouth.x, ball.position.y - mouth.y) < size * 0.45
        else { return }
        ball.carrier = self
        ball.velocity = .zero
        ballCarryUntil = now.addingTimeInterval(4)
        emotes.show(.heart)
    }

    /// Игра: ждёт броска, бежит к мячику, прыгает за ним, несёт пойманный к курсору. false — мячик неинтересен.
    private func playBall(on p: Platform, _ now: Date, _ dt: CGFloat) -> Bool {
        guard ball.isActive else { return false }
        func stand() { standStill() }
        func run(toward x: CGFloat) -> Bool { runStep(toward: x, on: p, dt) }

        if ball.isGrabbed {
            lookAt = ball.position  // ждёт броска
            stand()
            faceMouse(now)
            return true
        }
        if let carrier = ball.carrier, carrier !== self {
            lookAt = ball.position  // мячик у друга — смотрит с завистью
            stand()
            faceMouse(now)
            return now.timeIntervalSince(ball.touchedAt) < 25
        }
        if ball.carrier === self {
            // Несёт к курсору и кладёт перед ним
            if abs(mouse.x - centerX) > size * 0.8 && now < ballCarryUntil && run(toward: mouse.x) { return true }
            stand()
            ball.carrier = nil
            ball.position = mouth
            ball.velocity = CGVector(dx: direction * 120 * unit, dy: 200 * unit)
            ignoreBallUntil = now.addingTimeInterval(2.5)
            return true
        }
        guard now >= ignoreBallUntil, now.timeIntervalSince(ball.touchedAt) < 25 else { return false }
        lookAt = ball.position
        let dx = ball.position.x - centerX, dy = ball.position.y - origin.y
        // Мячик над головой — прыжок навстречу
        if abs(dx) < size * 1.6, dy > size * 0.7, dy < size * 4.5, now >= nextBallJump, ball.velocity.dy < 300 {
            nextBallJump = now.addingTimeInterval(0.8)
            hop(CGVector(dx: dx * 2.2, dy: sqrt(2 * Pet.gravity * unit * (dy - size * 0.3))))
            return true
        }
        if abs(dx) > size * 0.3 {
            if run(toward: ball.position.x) { return true }
            // Край кромки: мячик ниже — спрыгивает, лежит на другой кромке выше — запрыгивает туда
            if dy < -size * 0.5 {
                state = .walking
                walkingOff = true
                origin.x += direction * walkingSpeed * px * dt
                return true
            }
            let ballFloor = ball.position.y - ball.radius
            if ball.isResting, now >= nextBallJump,
               let target = world.platforms.first(where: { abs($0.y - ballFloor) < 3 && $0.holds(ball.position.x) }) {
                nextBallJump = now.addingTimeInterval(1)
                jump(to: target, x: min(max(ball.position.x, target.x0 + size * 0.35), target.x1 - size * 0.35))
                return true
            }
        }
        stand()
        faceMouse(now)
        return true
    }

    private func standStill() {
        if state != .idle {
            state = .idle
            stateTime = 0
        }
    }

    /// Шаг бегом к x по своей кромке; false — упёрся в край.
    private func runStep(toward x: CGFloat, on p: Platform, _ dt: CGFloat, speed: CGFloat? = nil) -> Bool {
        let speed = speed ?? Pet.runFactor
        let step = (x > centerX ? 1 : -1) * walkingSpeed * speed * px * dt
        let edge = size * 0.2
        guard centerX + step <= p.x1 - edge && centerX + step >= p.x0 + edge else { return false }
        if state != .walking {
            state = .walking
            stateTime = 0
        }
        direction = step > 0 ? 1 : -1
        running = speed > 1
        origin.x += step
        return true
    }

    // MARK: - Музыка и фото

    /// Пританцовывает несколько секунд, потом отдыхает и снова.
    private func danceNow() {
        nextDance = Date().addingTimeInterval(.random(in: 12...25))
        perform(Act(frames: looped(dance, for: .random(in: 5...9)), sway: (7, 0.07), notes: true, calm: true) { [unowned self] in
            rest(for: .random(in: 1...2))
        })
    }

    /// Делают скриншот — садится, машет лапкой и подмигивает.
    func poseForPhoto(duration: TimeInterval = 5) {
        photoPose.request(at: Date(), duration: duration)
        if state == .sleeping { wake(greet: false) }
        if ball.carrier === self { ball.carrier = nil }
    }

    // MARK: - Вдвоём

    private var friendNearby: Pet? {
        guard let friend, [.idle, .walking].contains(friend.state), friend.act == nil, friend.game == nil,
              friend.hide == nil, friend.trashTrip == nil,
              abs(friend.origin.y - origin.y) < 2, friend.supportID == supportID, abs(friend.centerX - centerX) < size * 12
        else { return nil }
        return friend
    }

    /// Иногда зовёт друга поиграть в догонялки или подходит пообниматься.
    private func playWithFriend() -> Bool {
        guard Date() >= nextFriendPlay, !staying, let friend = friendNearby, Double.random(in: 0..<1) < 0.3 else { return false }
        nextFriendPlay = Date().addingTimeInterval(.random(in: 40...90))
        friend.nextFriendPlay = nextFriendPlay
        let until = Date().addingTimeInterval(.random(in: 6...10))
        if Bool.random() {
            game = .chaser
            friend.game = .runner
            friend.emotes.show(.startle)
        } else {
            game = .visitor
        }
        gameUntil = until
        friend.gameUntil = until
        friend.act = nil
        friend.stopChasing()
        return true
    }

    /// Шаг игры: догоняет, убегает или идёт обниматься.
    private func playGame(on p: Platform, _ now: Date, _ dt: CGFloat) {
        guard let game, let friend, now < gameUntil, abs(friend.origin.y - origin.y) < 2,
              [.idle, .walking].contains(friend.state) || friend.state == .airborne
        else {
            endGame()
            return
        }
        let dx = friend.centerX - centerX
        lookAt = NSPoint(x: friend.centerX, y: friend.origin.y + size * 0.6)
        switch game {
        case .chaser:
            if abs(dx) < size * 0.45 && now >= gameSwapAt {
                // Догнал — теперь убегает он
                self.game = .runner
                friend.game = .chaser
                gameSwapAt = now.addingTimeInterval(1)
                friend.gameSwapAt = gameSwapAt
                friend.emotes.show(.startle)
            } else if !runStep(toward: friend.centerX, on: p, dt, speed: 1.8) {
                standStill()
            }
        case .runner:
            let away = centerX + (dx > 0 ? -1 : 1) * size
            if !runStep(toward: away, on: p, dt, speed: 1.7) {
                // Упёрся в край — разворачивается и проскакивает мимо догоняющего
                _ = runStep(toward: centerX + (dx > 0 ? 1 : -1) * size * 3, on: p, dt, speed: 1.7)
            }
        case .visitor:
            if abs(dx) > size * 0.7 {
                if !runStep(toward: friend.centerX, on: p, dt, speed: 1) { endGame() }
                return
            }
            // Подошёл: оба смотрят друг на друга, жмурятся, сердечки
            direction = dx > 0 ? 1 : -1
            friend.direction = -direction
            for pet in [self, friend] {
                pet.game = nil
                pet.emotes.show(.heart)
                pet.perform(Act(frames: pet.looped(pet.happy, for: 1.6), calm: true) { [unowned pet] in pet.rest(for: 1) })
            }
        }
    }

    private func endGame() {
        let wasPlaying = game == .chaser || game == .runner
        for pet in [self, friend].compactMap({ $0 }) where pet.game != nil {
            pet.game = nil
            if [.idle, .walking].contains(pet.state) { pet.rest(for: .random(in: 1...2)) }
            if wasPlaying { pet.emotes.show(.heart) }
        }
    }

    // MARK: - Опора и прыжки

    private func refreshWorld(_ now: Date) {
        guard now.timeIntervalSince(lastScan) > 0.05 else { return }
        lastScan = now
        if blocksEnabled { blockScanner.refresh(minWidth: size * 0.8) }
        world = World.scan(minWidth: size * 0.8, headroom: size, blocks: blocksEnabled ? blockScanner.latest : nil)
    }

    /// Платформа под лапами на текущей высоте.
    private func support() -> Platform? {
        world.platforms
            .filter { abs($0.y - origin.y) < 1.5 && $0.holds(centerX) }
            .min { ($0.windowID == supportID ? 0 : 1) < ($1.windowID == supportID ? 0 : 1) }
    }

    /// Если окно, на котором стоим, сдвинули — едем вместе с ним и запоминаем, как быстро оно движется.
    private func ride(_ dt: CGFloat) {
        guard supportID != 0, let old = supportFrame, let new = world.windowFrames[supportID], dt > 0 else {
            windowVelocity = .zero
            return
        }
        let dx = new.minX - old.minX, dy = new.maxY - old.maxY
        origin.x += dx
        origin.y += dy
        supportFrame = new
        // Рамки окон обновляются реже кадров, поэтому скорость сильно сглажена
        let k = min(dt * 6, 1)
        windowVelocity.dx += (dx / dt - windowVelocity.dx) * k
        windowVelocity.dy += (dy / dt - windowVelocity.dy) * k
    }

    /// Окно трясут: пригибается и держится, а при сильной тряске слетает. true — занят этим.
    private func holdOn(_ now: Date, _ dt: CGFloat) -> Bool {
        let speed = hypot(windowVelocity.dx, windowVelocity.dy)
        if speed > 3500 && Double.random(in: 0..<1) < 3 * Double(dt) {
            emotes.show(.startle)
            launch(CGVector(dx: windowVelocity.dx * 0.5, dy: 250 * unit + max(windowVelocity.dy, 0) * 0.5))
            return true
        }
        if speed > 1200 { clingUntil = now.addingTimeInterval(0.35) }
        guard now < clingUntil else { return false }
        stopChasing()
        act = nil
        if state != .idle {
            state = .idle
            stateTime = 0
        }
        return true
    }

    /// Выбирает платформу в пределах прыжка; dir ограничивает направление.
    private func jumpTarget(toward dir: CGFloat? = nil, from current: Platform?) -> (Platform, CGFloat)? {
        let margin = size * 0.35
        let options = world.platforms.compactMap { p -> (Platform, CGFloat)? in
            guard p.width >= size * 0.8 else { return nil }
            let lo = p.x0 + margin, hi = p.x1 - margin
            guard lo < hi else { return nil }
            let tx = min(max(centerX + (dir ?? (Bool.random() ? 1 : -1)) * .random(in: 60...300) * unit, lo), hi)
            let dx = tx - centerX, dy = p.y - origin.y
            if let dir, dx * dir < 10 * unit { return nil }
            guard abs(dx) <= 420 * unit, dy <= 320 * unit, dy >= -700 * unit else { return nil }
            if let current, current.windowID == p.windowID, abs(dy) < 1 { return nil }
            if abs(dy) < 20 * unit && abs(dx) < 80 * unit { return nil }
            return (p, tx)
        }
        return options.randomElement()
    }

    /// Баллистический прыжок с вершиной чуть выше старта и цели.
    private func jump(to p: Platform, x tx: CGFloat) {
        let g = Pet.gravity * unit
        let apex = max(origin.y, p.y) + .random(in: 30...70) * unit
        let up = sqrt(2 * g * (apex - origin.y))
        let time = up / g + sqrt(2 * (apex - p.y) / g)
        hop(CGVector(dx: (tx - centerX) / time, dy: up))
    }

    /// Дошли до края кромки окна: развернуться, перепрыгнуть или шагнуть вниз.
    private func reachEdge(of p: Platform) {
        if staying {
            direction = -direction
            return
        }
        if p.windowID == 0 {
            if Double.random(in: 0..<1) < 0.5, let area = wall(direction, of: p) {
                startClimb(area, from: p)
            } else if Double.random(in: 0..<1) < 0.4, let (t, x) = jumpTarget(toward: direction, from: p) {
                jump(to: t, x: x)
            } else {
                direction = -direction
            }
            return
        }
        switch Double.random(in: 0..<1) {
        case ..<0.35:
            direction = -direction
        case ..<0.7:
            if let (t, x) = jumpTarget(toward: direction, from: p) { jump(to: t, x: x) } else { fallthrough }
        default:
            stepOff()
        }
    }

    /// Шагнуть с края: иногда сначала балансирует, будто вот-вот свалится.
    private func stepOff() {
        guard Double.random(in: 0..<1) < 0.6 else {
            walkingOff = true
            return
        }
        perform(Act(frames: looped(balance, for: .random(in: 0.8...1.4)), sway: (13, 0.12)) { [unowned self] in
            state = .walking
            stateTime = 0
            walkingOff = true
        })
    }

    private func decideAfterRest() {
        if isNight && nightThings() { return }
        if rareEvent() || playWithFriend() || fidget() { return }
        let here = support()
        if !staying, Double.random(in: 0..<1) < 0.35, let (t, x) = jumpTarget(from: here) {
            jump(to: t, x: x)
        } else {
            stroll()
        }
    }

    // MARK: - Стены

    /// Видимая область экрана, если с этой стороны пола за краем нет другого экрана.
    private func wall(_ side: CGFloat, of floor: Platform) -> NSRect? {
        let x = side > 0 ? floor.x1 : floor.x0
        guard let area = NSScreen.screens.map(\.visibleFrame).first(where: { $0.contains(NSPoint(x: x - side, y: floor.y + 1)) }),
              area.height > size * 4
        else { return nil }
        let beyond = NSPoint(x: x + side * 2, y: floor.y + size)
        return NSScreen.screens.contains { $0.frame.contains(beyond) } ? nil : area
    }

    private func startClimb(_ area: NSRect, from floor: Platform) {
        stopChasing()
        walkingOff = false
        state = .climbing
        stateTime = 0
        wallSide = direction
        wallX = wallSide > 0 ? area.maxX : area.minX
        wallFloor = floor.y
        wallTop = area.maxY - size
        origin.x = wallSide > 0 ? wallX - size : wallX
        climbDir = 1
        climbHeadDown = false
        climbTarget = .random(in: min(wallFloor + size * 3, wallTop)...wallTop)
        climbPauseUntil = .distantPast
        supportID = 0
        supportFrame = nil
    }

    private func climb(_ now: Date, _ dt: CGFloat) {
        if climbDir == 0 {
            guard now >= climbPauseUntil else { return }
            // Повисел — лезет обратно или отталкивается и прыгает вниз, может, на окно
            if Double.random(in: 0..<1) < 0.45 {
                climbDir = -1
                climbHeadDown = true
                stateTime = 0
            } else {
                leaveWall()
            }
            return
        }
        if now < climbPauseUntil { return }
        origin.y += climbDir * walkingSpeed * px * 0.8 * dt
        if climbDir > 0 && origin.y >= climbTarget {
            origin.y = climbTarget
            climbDir = 0
            stateTime = 0
            climbPauseUntil = now.addingTimeInterval(.random(in: 0.8...3))
        } else if climbDir < 0 && origin.y <= wallFloor {
            origin.y = wallFloor
            stroll(-wallSide)  // слез — уходит от стены
        } else if Double.random(in: 0..<1) < 0.15 * Double(dt) {
            climbPauseUntil = now.addingTimeInterval(.random(in: 0.5...1.5))  // замер, огляделся
        }
    }

    /// Оттолкнуться от стены.
    private func leaveWall() {
        direction = -wallSide
        launch(CGVector(dx: -wallSide * .random(in: 150...350) * unit, dy: .random(in: 100...400) * unit))
    }

    // MARK: - Кадр

    private func parkInCorner() {
        stopChasing()
        act = nil
        state = .idle
        velocity = .zero
        napUntil = nil
        walkingOff = false
        supportID = 0
        direction = cornerSide == "left" ? 1 : -1
        origin = CornerSeat.origin(in: screenArea, size: size, order: cornerOrder, left: cornerSide == "left")
    }

    private func tick() {
        let now = Date()
        let dt = CGFloat(min(now.timeIntervalSince(lastTick), 0.1))
        lastTick = now
        stateTime += Double(dt)
        refreshWorld(now)
        trackMouse(now, dt)
        lookAt = nil
        running = false

        if cornerMode && state != .held {
            parkInCorner()
        } else {
            switch state {
            case .idle, .walking:
                if hide != nil {
                    hideStep(now, dt)  // за краем экрана опоры под лапами нет — это нормально
                    break
                }
                ride(dt)
                guard let p = support() else {
                    // Сошли с края или опору убрали из-под лап: окно закрыли, свернули, перекрыли, страницу прокрутили
                    if !walkingOff && state == .idle { emotes.show(.puzzled) }
                    stayUntil = .distantPast
                    launch(CGVector(dx: state == .walking ? direction * walkingSpeed * px : 0, dy: 0))
                    break
                }
                supportID = p.windowID
                if photoPose.isActive(at: now) {
                    stopChasing()
                    act = nil
                    walkingOff = false
                    state = .idle
                    stateUntil = now.addingTimeInterval(1)
                    break
                }
                if holdOn(now, dt) { break }
                if paused {
                    act = nil
                    if state != .idle {
                        state = .idle
                        stateTime = 0
                    }
                    faceMouse(now)
                    break
                }
                if enjoyPetting(now) { break }
                if let current = act {
                    if now >= current.end {
                        act = nil
                        current.then?()
                    }
                    break
                }
                if trashTrip != nil {
                    tripToTrash(on: p, now, dt)
                    break
                }
                if game != nil {
                    playGame(on: p, now, dt)
                    break
                }
                if butterfly.isActive && butterfly.target != nil {
                    watchButterfly(now)
                    break
                }
                if playBall(on: p, now, dt) { break }
                if musicPlaying && now >= nextDance && !chasing {
                    danceNow()
                    break
                }
                if !isReminding && sleepDelay > 0 && Pet.userIdleSeconds > sleepDelay {
                    stopChasing()
                    state = .sleeping
                    stateTime = 0
                    break
                }
                if chasesCursor && (chasing || startChase(now, dt)) {
                    chase(on: p, now, dt)
                    break
                }
                if state == .idle {
                    faceMouse(now)
                    maybeSwipe(now, dt)
                    if act == nil && now >= stateUntil { decideAfterRest() }
                    break
                }
                let step = direction * walkingSpeed * px * dt
                let edge = size * 0.2
                let atEdge = (direction > 0 && centerX + step > p.x1 - edge) || (direction < 0 && centerX + step < p.x0 + edge)
                if atEdge && !walkingOff {
                    reachEdge(of: p)
                } else {
                    origin.x += step
                    if !staying, Double.random(in: 0..<1) < 0.25 * Double(dt), let (t, x) = jumpTarget(toward: direction, from: p) {
                        jump(to: t, x: x)
                    } else if now >= stateUntil {
                        rest(for: .random(in: 2...6))
                    }
                }
            case .sleeping:
                ride(dt)
                if support() == nil {
                    launch(.zero)  // опору убрали — падает, просыпаясь
                } else if let napUntil {
                    if now >= napUntil { wake(greet: false) }  // ночная дрёма: мышь не будит
                } else if Pet.userIdleSeconds < 2 {
                    wake(greet: true)
                }
            case .held:
                dangle(dt)
            case .climbing:
                if !paused { climb(now, dt) }
            case .airborne:
                let prevY = origin.y
                velocity.dy -= Pet.gravity * unit * dt
                origin.x += velocity.dx * dt
                origin.y += velocity.dy * dt
                keepOnScreens()
                if curled { spin -= velocity.dx / (size * 0.5) * dt }  // катится клубком
                if velocity.dy <= 0 {
                    reachForButterfly()
                    let landing = world.platforms
                        .filter { $0.holds(centerX) && prevY >= $0.y - 0.5 && origin.y <= $0.y }
                        .max { $0.y < $1.y }
                    if let landing {
                        land(on: landing, impact: -velocity.dy)
                    } else if let floor = floorBelow(), origin.y < floor.y {
                        land(on: floor, impact: -velocity.dy)  // страховка: пролетели сквозь пол на большом шаге или окно уехало
                    }
                }
            }

        }
        if state != .held {
            window.setFrameOrigin(origin)
        }
        catchBallIfClose(now)
        ball.pixel = px
        ball.platforms = world.platforms
        ball.gravity = Pet.gravity * unit
        if ball.carrier === self { ball.position = mouth }
        butterfly.step(dt)
        updatePoop(now)

        var image: CGImage
        var facingLeft = direction < 0
        var tilt: CGFloat = 0, pivotY: CGFloat = 0.6, stretch: CGFloat = 1
        switch state {
        case .walking:
            image = walk.frame(at: stateTime * Double(movementSpeed) * Double(chasing || running ? Pet.runFactor : 1))
        case .held:
            image = hang.frame(at: stateTime)
            tilt = swing
        case .airborne where curled:
            image = curl.frames[0]
            tilt = spin
            pivotY = 0.5
        case .airborne:
            image = idle.frames[2]  // зажмурился
            stretch = 1 + min(abs(velocity.dy) / (4000 * unit), 0.12)  // в полёте вытягивается по ходу движения
        case .idle:
            if photoPose.isActive(at: now) {
                image = pose.frame(at: now.timeIntervalSince(photoPose.startedAt))
            } else if cornerMode {
                image = sit.frame(at: stateTime)
            } else if let act {
                image = act.frame(at: now)
                if let sway = act.sway {
                    tilt = sin(now.timeIntervalSince(act.start) * sway.speed) * sway.amount
                    pivotY = 0
                }
                if act.notes && now >= nextNote {
                    nextNote = now.addingTimeInterval(0.55)
                    emotes.show(.note)
                }
            } else if now < clingUntil {
                image = crouch.frames[0]  // вцепился в окно
                tilt = sin(now.timeIntervalSince1970 * 40) * 0.03
                pivotY = 0
            } else if isPetted {
                image = happy.frame(at: stateTime)
            } else {
                image = idleFrame(now)
            }
        case .climbing:
            image = climbDir == 0 || paused ? idle.frame(at: stateTime) : walk.frame(at: stateTime * Double(movementSpeed))
            // Поворот на четверть: лапы к стене. Справа носом вверх — без отражения, вниз — отражённый; слева наоборот.
            facingLeft = (wallSide > 0) == climbHeadDown
            tilt = wallSide * .pi / 2
            pivotY = 0.5
        case .sleeping:
            image = sleep.frame(at: stateTime)
        }
        view.show(image, facingLeft: facingLeft, tilt: tilt, pivotY: pivotY, stretch: stretch)
        followBubble()
        shadow.update(x: centerX, feet: origin.y, surface: surfaceBelow(), pixel: px, below: window)
        emotes.update(head: head, pixel: px)
        let outside = hide == nil && [.idle, .walking, .sleeping].contains(state)
        weatherFX.update(feet: NSPoint(x: centerX, y: origin.y), head: head, kind: outside ? weather : nil, pixel: px, above: window)
        updatePillow()
        updateTrinket(dt)
    }

    /// Куда падает тень: поверхность прямо под лапами. На стене тени нет.
    private func surfaceBelow() -> CGFloat? {
        if hide != nil { return nil }
        switch state {
        case .climbing: return nil
        case .idle, .walking, .sleeping: return origin.y
        case .held: return dropTarget()?.y ?? world.platforms.filter { $0.holds(centerX) && $0.y <= origin.y }.map(\.y).max()
        case .airborne: return world.platforms.filter { $0.holds(centerX) && $0.y <= origin.y + 0.5 }.map(\.y).max()
        }
    }

    private func idleFrame(_ now: Date) -> CGImage {
        let since = now.timeIntervalSince(landedAt)
        if since < (hardLanding ? 0.24 : 0.12) {
            return crouch.frames[hardLanding && since < 0.12 ? 0 : 1]
        }
        guard let gaze = gaze() else { return idle.frame(at: stateTime) }
        if stateTime.truncatingRemainder(dividingBy: 3.4) > 3.25 { return idle.frames[2] }  // моргнул
        return look.frames[Int(stateTime / 0.3) % 2 * 9 + gaze]
    }

    // MARK: - Сон

    /// Сколько прошло с последнего движения мыши или нажатия клавиши (любое устройство, без разрешений).
    static var userIdleSeconds: TimeInterval {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }

    /// Просыпается: потягивается и зевает, потом стоит.
    private func wake(greet: Bool) {
        guard state == .sleeping else { return }
        napUntil = nil
        let frames = [(wakeUp.frames[0], 1.0), (wakeUp.frames[1], 0.8)]
        perform(Act(frames: frames, calm: true) { [unowned self] in rest(for: .random(in: 1...2)) })
        if greet { onWake?() }
    }

    // MARK: - Ночь и сон Мака

    /// Ночью иногда зевает, а иногда достаёт подушку и дремлет минуту-две.
    private func nightThings() -> Bool {
        switch Double.random(in: 0..<1) {
        case ..<0.2:
            perform(Act(frames: [(wakeUp.frames[1], 1.1)], calm: true) { [unowned self] in rest(for: .random(in: 1...2)) })
        case ..<0.32:
            stopChasing()
            act = nil
            state = .sleeping
            stateTime = 0
            napUntil = Date().addingTimeInterval(.random(in: 40...120))
        default:
            return false
        }
        return true
    }

    /// Подушка под головой, когда спит ночью — позади питомца.
    private func updatePillow() {
        guard state == .sleeping && isNight else {
            if pillow.isVisible { pillow.hide() }
            return
        }
        let wasVisible = pillow.isVisible
        pillow.show(Arts.pillow, center: NSPoint(x: origin.x + size * (direction > 0 ? 0.7 : 0.3), y: origin.y + px * 5), pixel: px)
        if !wasVisible { pillow.panel.order(.below, relativeTo: window.windowNumber) }
    }

    /// Мак проснулся — питомец тоже: потягивается и зевает.
    func macWoke() {
        if state == .sleeping {
            wake(greet: false)
        } else if state == .idle || state == .walking, hide == nil {
            perform(Act(frames: [(wakeUp.frames[0], 1.0), (wakeUp.frames[1], 0.8)], calm: true) { [unowned self] in rest(for: 1) })
        }
    }

    // MARK: - Корзина

    /// Что-то выбросили (или просто захотелось) — бежит к Корзине в Доке.
    func goToTrash() {
        guard !cornerMode else { return }
        guard state == .idle || state == .walking, hide == nil, game == nil, !paused, trashTrip == nil else { return }
        stopChasing()
        act = nil
        trashTrip = MacEvents.trashInDock()?.x ?? screenArea.maxX - size
    }

    private func tripToTrash(on p: Platform, _ now: Date, _ dt: CGFloat) {
        guard let x = trashTrip else { return }
        if p.windowID != 0 {
            // Сначала на пол: бежит к краю окна и спрыгивает
            if !runStep(toward: x, on: p, dt, speed: 1.6) {
                state = .walking
                walkingOff = true
                direction = x > centerX ? 1 : -1
                origin.x += direction * walkingSpeed * px * dt
            }
            return
        }
        let target = min(max(x, p.x0 + size * 0.3), p.x1 - size * 0.3)
        if abs(target - centerX) > size * 0.15 && runStep(toward: target, on: p, dt, speed: 1.6) { return }
        trashTrip = nil
        rummage()
    }

    /// Заглядывает вниз, роется, вытаскивает находку, хвастается и бросает.
    private func rummage() {
        let find = Arts.trinkets.randomElement()!
        let dig = (0..<8).map { (potty.frames[2 + $0 % 2], 0.13) }
        sequence([
            ([(look.frames[7], 0.8)], nil),
            (dig, nil),
            (looped(happy, for: 2.2), { [unowned self] in
                trinketArt = find.art
                trinketCarried = true
                emotes.show(.startle)
                onSay?("Смотри, что я нашёл в Корзине: \(find.name)!")
            }),
            ([(idle.frames[0], 0.3)], { [unowned self] in dropTrinket() }),
        ])
    }

    private func dropTrinket() {
        trinketCarried = false
        trinketDrop = (mouth, 0, Date())
    }

    /// Находка в зубах, а брошенная — падает на пол и тает.
    private func updateTrinket(_ dt: CGFloat) {
        guard let art = trinketArt else { return }
        if trinketCarried {
            trinket.show(art, center: mouth, pixel: px)
            return
        }
        guard var drop = trinketDrop else {
            trinket.hide()
            trinketArt = nil
            return
        }
        drop.vy -= Pet.gravity * unit * dt
        drop.position.y = max(drop.position.y + drop.vy * dt, origin.y + CGFloat(art.height) / 2 * px)
        trinketDrop = drop
        let t = Date().timeIntervalSince(drop.since)
        let alpha = t < 2 ? 1 : max(0, 1 - CGFloat(t - 2))
        if alpha <= 0 {
            trinketDrop = nil
        } else {
            trinket.show(art, center: drop.position, pixel: px, alpha: alpha)
        }
    }

    // MARK: - Прятки

    /// Прячется за окно, которое доходит до пола, а если такого нет — за край экрана. Торчит только хвост.
    private func startHide(on p: Platform) -> Bool {
        guard p.windowID == 0 else { return false }
        var spots: [Hide] = []
        for (id, f) in world.windowFrames where f.minY <= p.y + size * 0.2 && f.maxY >= p.y + size * 1.2 && f.width > size * 2 {
            if f.minX - size > p.x0 && f.minX < p.x1 { spots.append(Hide(x: f.minX - size * 0.3, facing: 1, behind: id, frame: f)) }
            if f.maxX + size < p.x1 && f.maxX > p.x0 { spots.append(Hide(x: f.maxX - size * 0.7, facing: -1, behind: id, frame: f)) }
        }
        if spots.isEmpty {
            if wall(-1, of: p) != nil { spots.append(Hide(x: p.x0 - size * 0.7, facing: -1)) }
            if wall(1, of: p) != nil { spots.append(Hide(x: p.x1 - size * 0.3, facing: 1)) }
        }
        guard let spot = spots.min(by: { abs($0.x - origin.x) < abs($1.x - origin.x) }) else { return false }
        stopChasing()
        act = nil
        hide = spot
        return true
    }

    private func hideStep(_ now: Date, _ dt: CGFloat) {
        guard var h = hide else { return }
        guard let until = h.until else {
            // Бежит к укрытию, не глядя на края кромки
            let dx = h.x - origin.x, step = walkingSpeed * 1.6 * px * dt
            if abs(dx) > step {
                if state != .walking {
                    state = .walking
                    stateTime = 0
                }
                direction = dx > 0 ? 1 : -1
                running = true
                origin.x += direction * step
                return
            }
            origin.x = h.x
            direction = h.facing
            state = .idle
            stateTime = 0
            if let id = h.behind {
                window.level = .normal
                window.order(.below, relativeTo: Int(id))
            }
            h.until = now.addingTimeInterval(.random(in: 30...75))
            hide = h
            return
        }
        // Окно сдвинули или закрыли, или надоело ждать — выходит сам
        if let id = h.behind, world.windowFrames[id] != h.frame { comeOut(found: false) }
        if now >= until { comeOut(found: false) }
    }

    private func comeOut(found: Bool) {
        guard let h = hide else { return }
        hide = nil
        window.level = .floating
        window.orderFrontRegardless()
        if let floor = floorBelow() { origin.x = min(max(origin.x, floor.x0 - size * 0.3), floor.x1 - size * 0.7) }
        if found {
            emotes.show(.heart)
            onSay?("Ты меня нашёл! 🎉")
            hop(CGVector(dx: -h.facing * 250 * unit, dy: 600 * unit))
        } else {
            onSay?("Не нашёл меня? А я прятался тут 😉")
            stroll(-h.facing)
        }
    }

    // MARK: - Курсор

    private func trackMouse(_ now: Date, _ dt: CGFloat) {
        let m = NSEvent.mouseLocation
        let moved = hypot(m.x - mouse.x, m.y - mouse.y)
        if moved > 0.5 { mouseMovedAt = now }
        mouseSpeed += (moved / max(dt, 0.001) - mouseSpeed) * min(dt * 8, 1)
        trackStrokes(dx: m.x - mouse.x, now)
        mouse = m
    }

    /// Гладят: курсор над питомцем ходит туда-сюда — четыре смены направления за полторы секунды.
    private func trackStrokes(dx: CGFloat, _ now: Date) {
        guard abs(dx) > 1, window.frame.insetBy(dx: -size * 0.1, dy: -size * 0.1).contains(mouse) else { return }
        let dir: CGFloat = dx > 0 ? 1 : -1
        if dir != strokeDir {
            strokeDir = dir
            strokes.append(now)
        }
        strokes.removeAll { now.timeIntervalSince($0) > 1.5 }
        if strokes.count >= 4 {
            if now >= pettedUntil && now >= nextPurr {
                nextPurr = now.addingTimeInterval(10)
                onPetted?()
            }
            pettedUntil = now.addingTimeInterval(0.7)
        }
    }

    private var isPetted: Bool { Date() < pettedUntil }

    /// Жмурится и пускает сердечки, пока гладят. Прыжок с подготовкой не перебивает.
    private func enjoyPetting(_ now: Date) -> Bool {
        guard isPetted, act?.calm ?? true else { return false }
        stopChasing()
        act = nil
        if state != .idle {
            state = .idle
            stateTime = 0
        }
        stateUntil = max(stateUntil, now.addingTimeInterval(1))
        if now >= nextHeart {
            nextHeart = now.addingTimeInterval(0.35)
            emotes.show(.heart)
        }
        return true
    }

    /// Курсор у самых лап спереди — иногда бьёт по нему лапкой.
    private func maybeSwipe(_ now: Date, _ dt: CGFloat) {
        let dx = (mouse.x - centerX) * direction, dy = mouse.y - origin.y
        guard now >= nextSwipe, dx > size * 0.3, dx < size * 1.1, dy > 0, dy < size * 0.6,
              Double.random(in: 0..<1) < 2.5 * Double(dt)
        else { return }
        nextSwipe = now.addingTimeInterval(.random(in: 1.2...2.5))
        perform(Act(frames: [(swipe.frames[0], 0.1), (swipe.frames[1], 0.16), (swipe.frames[0], 0.1)], calm: true))
    }

    /// Курсор недавно двигался неподалёку — есть на что смотреть.
    private var mouseInteresting: Bool {
        (chasing || Date().timeIntervalSince(mouseMovedAt) < 3)
            && hypot(mouse.x - centerX, mouse.y - origin.y) < size * 25
    }

    /// Номер кадра взгляда в листе look: (gy + 1) * 3 + gx + 1, gx вперёд по морде, gy вниз.
    private func gaze() -> Int? {
        guard lookAt != nil || mouseInteresting else { return nil }
        let eyeX = origin.x + size * (direction < 0 ? 0.3 : 0.7), eyeY = origin.y + size * 0.53
        let dx = (focus.x - eyeX) * direction, dy = focus.y - eyeY
        let gx = abs(dx) < size * 0.4 ? 0 : dx > 0 ? 1 : -1
        let gy = dy > max(abs(dx) * 0.4, size * 0.4) ? -1 : dy < -max(abs(dx) * 0.4, size * 0.3) ? 1 : 0
        return (gy + 1) * 3 + gx + 1
    }

    /// На что смотрит: мячик или бабочка, а если их нет — курсор.
    private var focus: NSPoint { lookAt ?? mouse }

    /// Стоит и курсор (мячик, бабочка) оказался за спиной — повернуться, но не чаще раза в полсекунды.
    private func faceMouse(_ now: Date) {
        guard lookAt != nil || mouseInteresting, (focus.x - centerX) * direction < -size * 0.6,
              now.timeIntervalSince(lastTurn) > 0.6 else { return }
        direction = -direction
        lastTurn = now
    }

    /// Курсор быстро пронёсся рядом — иногда срывается за ним.
    private func startChase(_ now: Date, _ dt: CGFloat) -> Bool {
        guard now >= nextChase, mouseSpeed > 250, now.timeIntervalSince(mouseMovedAt) < 0.2,
              abs(mouse.x - centerX) < size * 12, (-size...size * 6).contains(mouse.y - origin.y),
              Double.random(in: 0..<1) < 1.2 * Double(dt)
        else { return false }
        chasing = true
        walkingOff = false
        chaseUntil = now.addingTimeInterval(.random(in: 3...7))
        emotes.show(.startle)
        return true
    }

    /// Бежит под курсор по своей кромке, с края не прыгает. Добежал — смотрит, а если курсор
    /// висит прямо над головой, может подпрыгнуть за ним.
    private func chase(on p: Platform, _ now: Date, _ dt: CGFloat) {
        let dx = mouse.x - centerX, dy = mouse.y - origin.y
        if now >= chaseUntil || abs(dx) > size * 16 || dy > size * 8 || dy < -size * 2 {
            stopChasing()
            rest(for: .random(in: 1...2.5))
            return
        }
        let step = (dx > 0 ? 1 : -1) * walkingSpeed * Pet.runFactor * px * dt
        let edge = size * 0.2
        let blocked = centerX + step > p.x1 - edge || centerX + step < p.x0 + edge
        if abs(dx) > size * 0.35 && !blocked {
            if state != .walking {
                state = .walking
                stateTime = 0
            }
            direction = dx > 0 ? 1 : -1
            origin.x += step
            return
        }
        if state != .idle {
            state = .idle
            stateTime = 0
        }
        faceMouse(now)
        let above = dy - size * 0.5
        if abs(dx) < size * 0.6, above > size * 0.3, above < size * 3, Double.random(in: 0..<1) < 1.5 * Double(dt) {
            let g = Pet.gravity * unit
            hop(CGVector(dx: dx * 2, dy: sqrt(2 * g * (above + size * 0.3))))
        } else {
            maybeSwipe(now, dt)
        }
    }

    private func stopChasing() {
        guard chasing else { return }
        chasing = false
        nextChase = Date().addingTimeInterval(.random(in: 12...30))
    }

    /// Висит за шкирку: тело отстаёт от руки и раскачивается, как маятник.
    private func dangle(_ dt: CGFloat) {
        guard dt > 0 else { return }
        handSpeed += ((origin.x - handX) / dt - handSpeed) * min(dt * 12, 1)
        handX = origin.x
        handVY += ((origin.y - handY) / dt - handVY) * min(dt * 12, 1)
        handY = origin.y
        let target = min(max(-handSpeed / 4000, -0.25), 0.25)
        swingSpeed += (120 * (target - swing) - 5 * swingSpeed) * dt
        swing = min(max(swing + swingSpeed * dt, -0.3), 0.3)
    }

    private func floorBelow() -> Platform? {
        world.platforms.filter { $0.windowID == 0 && $0.holds(centerX) }.first
            ?? world.platforms.filter { $0.windowID == 0 }.min { abs($0.x0 - centerX) < abs($1.x0 - centerX) }
    }

    /// Не улетать за края экранов. Врезался в боковой край с разгона — сворачивается клубком и отпружинивает.
    private func keepOnScreens() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        guard let minX = screens.map(\.minX).min(), let maxX = screens.map(\.maxX).max(),
              let maxY = screens.map(\.maxY).max() else { return }
        if origin.x < minX || origin.x + size > maxX {
            let wall: CGFloat = origin.x < minX ? -1 : 1
            origin.x = min(max(origin.x, minX), maxX - size)
            if abs(velocity.dx) > 700 * unit {
                curled = true
                velocity.dx = -velocity.dx * 0.6
                velocity.dy = max(velocity.dy, 0) + 250 * unit
                dust.puff(at: NSPoint(x: wall > 0 ? maxX : minX, y: origin.y + size * 0.3), pixel: px, strength: 0.5,
                          below: window, side: -wall)
            } else {
                velocity.dx = -velocity.dx * 0.3
            }
        }
        if origin.y + size > maxY {
            origin.y = maxY - size
            velocity.dy = -abs(velocity.dy) * 0.5
        }
    }
}
