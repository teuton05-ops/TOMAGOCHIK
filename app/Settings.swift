import AppKit
import SwiftUI

@MainActor
final class SettingsModel: ObservableObject {
    @Published var preferences: PetPreferences {
        didSet {
            if preferences != oldValue { onChange?(preferences) }
        }
    }
    var onChange: ((PetPreferences) -> Void)?
    var onPose: (() -> Void)?

    init(_ preferences: PetPreferences) { self.preferences = preferences }
}

@MainActor
final class SettingsWindow: NSObject, NSWindowDelegate {
    private let window: NSWindow
    let model: SettingsModel

    init(preferences: PetPreferences) {
        model = SettingsModel(preferences)
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 660),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: false)
        super.init()
        window.title = "Настройки Тамагочи"
        window.minSize = NSSize(width: 800, height: 590)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.contentView = NSHostingView(rootView: SettingsView(model: model))
        window.setFrameAutosaveName("TamagochiSettings")
        if !window.setFrameUsingName("TamagochiSettings") { window.center() }
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

private enum SettingsSection: String, CaseIterable, Identifiable {
    case pets = "Питомцы", appearance = "Внешний вид", behavior = "Поведение", help = "Доступ и помощь"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .pets: return "pawprint"
        case .appearance: return "paintpalette"
        case .behavior: return "slider.horizontal.3"
        case .help: return "hand.raised"
        }
    }
    var subtitle: String {
        switch self {
        case .pets: return "Кто будет жить на вашем рабочем столе"
        case .appearance: return "Ваш питомец, ваши любимые цвета"
        case .behavior: return "Пусть у вашего питомца будет свой характер"
        case .help: return "Всё, что нужно для комфортной жизни на Mac"
        }
    }
}

private struct SettingsView: View {
    @ObservedObject var model: SettingsModel
    @State private var section: SettingsSection = .pets
    @State private var trusted = BlockScanner.trusted
    @State private var confirmReset = false
    private let accessTimer = Timer.publish(every: 2, on: .main, in: .common).autoconnect()
    private let accent = Color(red: 0.72, green: 0.35, blue: 0.15)

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 24) {
                Label("Тамагочи", systemImage: "pawprint.fill")
                    .font(.system(size: 19, weight: .semibold))
                    .padding(.top, 12)
                VStack(spacing: 6) {
                    ForEach(SettingsSection.allCases) { item in
                        Button { section = item } label: {
                            Label(item.rawValue, systemImage: item.icon)
                                .font(.system(size: 13, weight: section == item ? .semibold : .regular))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 11)
                                .foregroundStyle(section == item ? accent : Color.primary)
                                .background(section == item ? accent.opacity(0.11) : .clear,
                                            in: RoundedRectangle(cornerRadius: 9))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(section == item ? [.isSelected] : [])
                    }
                }
                Spacer()
                Button("Сбросить настройки…") { confirmReset = true }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.secondary)
                Text("Маленький друг.\nБольшая компания.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).lineSpacing(4)
            }
            .padding(20).frame(width: 196)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(section.rawValue).font(.system(size: 29, weight: .bold))
                    Text(section.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(.bottom, 26)
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        switch section {
                        case .pets: pets
                        case .appearance: appearance
                        case .behavior: behavior
                        case .help: help
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 24)
                }.id(section)
                Divider()
                Label("Изменения сохраняются автоматически", systemImage: "checkmark.circle")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 15)
            }
            .padding(30).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .tint(accent)
        .onReceive(accessTimer) { _ in trusted = BlockScanner.trusted }
        .alert("Вернуть исходные настройки?", isPresented: $confirmReset) {
            Button("Отмена", role: .cancel) {}
            Button("Сбросить") { model.preferences = .standard }
        } message: {
            Text("Питомец, оформление и поведение вернутся к исходным значениям. Напоминания и файлы в зубах сохранятся.")
        }
    }

    private var pets: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 12) {
                petChoice("cat", title: "Котик", subtitle: "Любопытный непоседа", species: [.cat])
                petChoice("dog", title: "Собачка", subtitle: "Верный друг", species: [.dog])
                petChoice("duo", title: "Вместе", subtitle: "Вдвое веселее", species: [.cat, .dog])
            }
            group("Размер на экране", subtitle: "Применяется сразу к обоим питомцам") {
                sizeControl
            }
            group("Всегда рядом", subtitle: "Питомцы гуляют по рабочему столу и окнам.") {
                Label("Погладьте курсором, перетащите мышкой или предложите мячик из меню лапки.",
                      systemImage: "cursorarrow.motionlines")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func petChoice(_ value: String, title: String, subtitle: String, species: [Species]) -> some View {
        let selected = model.preferences.selection == value
        return Button { model.preferences.selection = value } label: {
            VStack(spacing: 8) {
                HStack(spacing: -25) {
                    ForEach(species, id: \.rawValue) { pet in
                        if let image = Self.sprite(pet, coat: pet == .cat ? model.preferences.catCoat : model.preferences.dogCoat) {
                            Image(nsImage: image).interpolation(.none).resizable()
                                .scaledToFit().frame(maxWidth: 110, maxHeight: 110)
                                .opacity(model.preferences.opacity)
                        }
                    }
                }.frame(height: 118)
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? accent : Color.secondary.opacity(0.4)).padding(.top, 5)
            }
            .padding(.vertical, 18).frame(maxWidth: .infinity)
            .background(selected ? accent.opacity(0.06) : Color(nsColor: .windowBackgroundColor),
                        in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(selected ? accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
            .contentShape(RoundedRectangle(cornerRadius: 14))
        }.buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(selected ? "Выбран" : "Не выбран")
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 26) {
            coatControl(.cat, selection: $model.preferences.catCoat)
            Divider()
            coatControl(.dog, selection: $model.preferences.dogCoat)
            Divider()
            group("Размер на экране", subtitle: "Одинаковый для обоих друзей; от 50% до 200%") {
                sizeControl
            }
            adjustment("Непрозрачность", value: $model.preferences.opacity, range: 0.35...1, step: 0.05,
                       valueLabel: "\(Int((model.preferences.opacity * 100).rounded()))%")
        }
    }

    private func coatControl(_ species: Species, selection: Binding<PetCoat>) -> some View {
        HStack(alignment: .center, spacing: 20) {
            if let image = Self.sprite(species, coat: selection.wrappedValue) {
                Image(nsImage: image).interpolation(.none).resizable().scaledToFit()
                    .frame(width: 112, height: 112).opacity(model.preferences.opacity)
                    .accessibilityLabel("Предпросмотр: \(species.title), \(selection.wrappedValue.title)")
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("Окрас: \(species.title.lowercased())").font(.system(size: 15, weight: .semibold))
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 8) {
                    ForEach(PetCoat.allCases) { coat in
                        Button { selection.wrappedValue = coat } label: {
                            HStack(spacing: 7) {
                                Circle().fill(Color(nsColor: coat.swatch)).frame(width: 14, height: 14)
                                Text(coat.title).font(.system(size: 11))
                                Spacer(minLength: 0)
                                if selection.wrappedValue == coat {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold))
                                }
                            }
                            .padding(9).frame(maxWidth: .infinity)
                            .background(selection.wrappedValue == coat ? accent.opacity(0.13) : Color(nsColor: .windowBackgroundColor),
                                        in: RoundedRectangle(cornerRadius: 7))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(species.title): \(coat.title)")
                            .accessibilityValue(selection.wrappedValue == coat ? "Выбран" : "Не выбран")
                    }
                }
            }
        }
    }

    private var sizeControl: some View {
        VStack(alignment: .leading, spacing: 12) {
            adjustment("Размер питомцев", value: $model.preferences.scale, range: 1...4, step: 0.1,
                       valueLabel: "\(Int((model.preferences.scale * 50).rounded()))%")
            HStack(spacing: 8) {
                ForEach([1.5, 2, 2.5], id: \.self) { scale in
                    Button(scale == 1.5 ? "Маленький" : scale == 2 ? "Средний" : "Большой") {
                        model.preferences.scale = scale
                    }.controlSize(.small)
                }
            }
        }
    }

    private func adjustment(_ title: String, value: Binding<Double>, range: ClosedRange<Double>,
                            step: Double, valueLabel: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer()
                Text(valueLabel).font(.system(size: 12, weight: .semibold, design: .monospaced)).foregroundStyle(.secondary)
            }
            Slider(value: value, in: range, step: step).accessibilityLabel(title)
        }
    }

    private var behavior: some View {
        VStack(alignment: .leading, spacing: 0) {
            option("Сидеть в уголке", detail: "Питомцы спокойно сидят в нижнем углу и не гуляют. Напоминания и работа с файлами продолжают работать.",
                   icon: "arrow.down.right.square", isOn: $model.preferences.cornerMode)
            if model.preferences.cornerMode {
                Picker("Угол экрана", selection: $model.preferences.cornerSide) {
                    Text("Нижний левый").tag("left")
                    Text("Нижний правый").tag("right")
                }.padding(.top, 14)
            }
            Divider().padding(.vertical, 22)
            group("Ритм жизни", subtitle: "От неторопливого компаньона до энергичного непоседы") {
                VStack(alignment: .leading, spacing: 18) {
                    adjustment("Скорость прогулки", value: $model.preferences.speed, range: 0.5...2, step: 0.25,
                               valueLabel: model.preferences.speed.formatted(.number.precision(.fractionLength(0...2))) + "×")
                    Picker("Сон без активности", selection: $model.preferences.sleepMinutes) {
                        Text("Через 1 минуту").tag(1.0)
                        Text("Через 3 минуты").tag(3.0)
                        Text("Через 5 минут").tag(5.0)
                        Text("Через 10 минут").tag(10.0)
                        Text("Через 15 минут").tag(15.0)
                        Text("Через 30 минут").tag(30.0)
                        Text("Не засыпать от бездействия").tag(0.0)
                    }
                    option("Ловить курсор", detail: "Питомец замечает движение мыши и иногда бежит за курсором.",
                           icon: "cursorarrow.motionlines", isOn: $model.preferences.chasesCursor)
                }
            }
            Divider().padding(.vertical, 22)
            option("Болтовня и подсказки", detail: "Приветствия, короткие реплики и полезные сочетания клавиш. Напоминания работают и без болтовни.",
                   icon: "text.bubble", isOn: $model.preferences.chatter)
            Picker("Частота болтовни", selection: $model.preferences.chatFrequency) {
                Text("Пореже").tag(0.5)
                Text("Обычно").tag(1.0)
                Text("Почаще").tag(2.0)
            }.padding(.top, 14).disabled(!model.preferences.chatter)
            Divider().padding(.vertical, 18)
            option("Звук напоминаний", detail: "Проигрывать короткий сигнал, когда наступает время напоминания.",
                   icon: "bell", isOn: $model.preferences.reminderSound)
            Divider().padding(.vertical, 18)
            option("Танцевать под музыку", detail: "Питомцы пританцовывают, когда на Mac играет музыка.",
                   icon: "music.note", isOn: $model.preferences.music)
            Divider().padding(.vertical, 18)
            option("Позировать для скриншота", detail: "Питомцы машут лапкой, когда вы делаете снимок экрана.",
                   icon: "camera", isOn: $model.preferences.screenshots)
            Button("Позировать сейчас — 30 секунд") { model.onPose?() }
                .padding(.top, 12)
                .help("Подготовить питомцев перед мгновенным снимком экрана")
            Divider().padding(.vertical, 18)
            option("Гулять по элементам окон", detail: "Использовать кнопки, изображения и другие элементы как площадки. Нужен Универсальный доступ.",
                   icon: "macwindow", isOn: $model.preferences.blocks)
        }
    }

    private var help: some View {
        VStack(alignment: .leading, spacing: 24) {
            group("Универсальный доступ", subtitle: "Позволяет питомцам гулять по элементам других приложений.") {
                HStack {
                    Label(trusted ? "Доступ разрешён" : "Доступ пока не разрешён",
                          systemImage: trusted ? "checkmark.circle.fill" : "exclamationmark.circle")
                        .foregroundStyle(trusted ? Color.green : Color.secondary)
                    Spacer()
                    Button("Открыть настройки macOS") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }.font(.system(size: 12))
            }
            group("Как общаться с питомцем", subtitle: "Все действия — прямо на рабочем столе") {
                VStack(alignment: .leading, spacing: 16) {
                    hint("hand.tap", "Один клик", "Питомец подпрыгнет.")
                    hint("alarm", "Двойной клик", "Создать напоминание.")
                    hint("cursorarrow", "Правый клик", "Быстрые действия и настройки.")
                    hint("doc", "Перетащить файл", "Питомец подержит его в зубах. Заберите файл перетаскиванием обратно.")
                }
            }
            Text("Окно можно закрыть: питомцы продолжат жить на рабочем столе. Чтобы открыть его снова, нажмите лапку в строке меню → Настройки…")
                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }

    private func group<Content: View>(_ title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 15, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
            }
            content()
        }
    }

    private func option(_ title: String, detail: String, icon: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(accent).frame(width: 24).padding(.top, 2)
            Toggle(isOn: isOn) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(title).font(.system(size: 14, weight: .semibold))
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.toggleStyle(.switch)
                .accessibilityLabel(title)
                .accessibilityHint(detail)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func hint(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(accent)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.font(.system(size: 12))
    }

    private static func sprite(_ species: Species, coat: PetCoat = .original) -> NSImage? {
        guard let url = Bundle.main.url(forResource: "\(species.rawValue)_idle", withExtension: "png", subdirectory: "sprites"),
              let image = NSImage(contentsOf: url)?.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let frame = image.cropping(to: CGRect(x: 0, y: 0, width: image.height, height: image.height)) else { return nil }
        return NSImage(cgImage: coat.render(frame), size: NSSize(width: 128, height: 128))
    }
}
