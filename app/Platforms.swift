import AppKit

/// Горизонтальная кромка, по которой можно ходить. Координаты Cocoa: y растёт вверх.
struct Platform {
    var x0: CGFloat
    var x1: CGFloat
    var y: CGFloat
    /// 0 — пол экрана, иначе номер окна, на котором лежит платформа (его верхняя кромка или блок внутри).
    var windowID: CGWindowID

    var width: CGFloat { x1 - x0 }
    func holds(_ x: CGFloat) -> Bool { x >= x0 && x <= x1 }
}

/// Снимок того, по чему можно ходить: низ каждого экрана, видимые куски верхних кромок окон
/// и блоки переднего окна. Координаты окон macOS отдаёт без разрешения на запись экрана.
struct World {
    var platforms: [Platform] = []
    var windowFrames: [CGWindowID: CGRect] = [:]

    static func scan(minWidth: CGFloat, headroom: CGFloat, blocks: Blocks?) -> World {
        var world = World()
        let screens = NSScreen.screens
        guard let primary = screens.first else { return world }
        for s in screens {
            world.platforms.append(Platform(x0: s.visibleFrame.minX, x1: s.visibleFrame.maxX, y: s.visibleFrame.minY, windowID: 0))
        }

        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let info = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return world }
        let me = ProcessInfo.processInfo.processIdentifier
        let flip = primary.frame.maxY  // у CoreGraphics y идёт вниз от верха главного экрана
        var nearer: [CGRect] = []  // список идёт спереди назад: всё, что уже прошли, лежит поверх текущего окна

        for w in info {
            guard (w[kCGWindowLayer as String] as? Int) == 0,
                  (w[kCGWindowOwnerPID as String] as? pid_t) != me,
                  (w[kCGWindowAlpha as String] as? Double ?? 1) > 0.1,
                  let id = w[kCGWindowNumber as String] as? CGWindowID,
                  let dict = w[kCGWindowBounds as String] as? NSDictionary,
                  let cg = CGRect(dictionaryRepresentation: dict)
            else { continue }
            let frame = CGRect(x: cg.minX, y: flip - cg.maxY, width: cg.width, height: cg.height)
            defer { nearer.append(frame) }
            world.windowFrames[id] = frame
            guard frame.height >= 60,
                  let screen = screens.first(where: { $0.frame.contains(NSPoint(x: frame.midX, y: frame.midY)) })
            else { continue }

            /// Кладёт кромку на высоте y, вырезая куски, которые закрыты окнами поверх.
            func add(_ a: CGFloat, _ b: CGFloat, y: CGFloat) {
                guard y + headroom <= screen.visibleFrame.maxY, y > screen.visibleFrame.minY else { return }
                var spans = [(max(a, frame.minX, screen.visibleFrame.minX), min(b, frame.maxX, screen.visibleFrame.maxX))]
                for r in nearer where r.minY <= y + headroom / 2 && r.maxY >= y {
                    spans = spans.flatMap { a, b -> [(CGFloat, CGFloat)] in
                        if r.maxX <= a || r.minX >= b { return [(a, b)] }
                        return [(a, r.minX), (r.maxX, b)].filter { $0.1 > $0.0 }
                    }
                }
                for (a, b) in spans where b - a >= minWidth {
                    world.platforms.append(Platform(x0: a, x1: b, y: y, windowID: id))
                }
            }

            add(frame.minX, frame.maxX, y: frame.maxY)

            // Блоки снимались чуть раньше: сдвигаем их вслед за окном, если его успели подвинуть
            if let blocks, blocks.windowID == id {
                let dx = cg.minX - blocks.windowFrame.minX, dy = cg.minY - blocks.windowFrame.minY
                for top in mergedTops(blocks.rects) {
                    add(top.x0 + dx, top.x1 + dx, y: flip - (top.y + dy))
                }
            }
        }
        return world
    }

    /// Вложенные блоки часто начинаются на одной высоте — склеиваем такие кромки в одну.
    private static func mergedTops(_ rects: [CGRect]) -> [(x0: CGFloat, x1: CGFloat, y: CGFloat)] {
        var tops: [(x0: CGFloat, x1: CGFloat, y: CGFloat)] = []
        for r in rects.sorted(by: { ($0.minY, $0.minX) < ($1.minY, $1.minX) }) {
            if let last = tops.last, abs(last.y - r.minY) < 3, r.minX <= last.x1 {
                tops[tops.count - 1].x1 = max(last.x1, r.maxX)
            } else {
                tops.append((r.minX, r.maxX, r.minY))
            }
        }
        return tops
    }
}
