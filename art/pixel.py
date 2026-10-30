"""Маленький движок пиксель-арта: слои с автообводкой, сборка спрайт-листов и превью.

Позы размечены в клетках сетки 32×32 (так их удобно двигать), а рисуются в пикселях 128×128:
каждая фигура растеризуется заново, поэтому скругления плавные, лапы — ровные наклонные полосы.
Мимика использует отдельную разметку 48×48, детали рисуются в полном разрешении."""
from math import ceil, floor

from PIL import Image, ImageDraw, ImageOps

OUTLINE = (43, 29, 26, 255)
GROUND = 30  # нижний ряд заливки в клетках; обводка лапок ложится под ним
S = 4  # пикселей на клетку; геометрия растеризуется сразу в полном разрешении
SIZE = 128
FACE_SCALE = SIZE / 48  # отдельная, историческая система координат мимики

# Цикл ходьбы, общий для всех четвероногих: (ближние, дальние, bob).
# Лапы — (x, dx, lift) для задней и передней. Поднимается та лапа, что была сзади:
# она переносится вперёд, а опорная едет назад.
WALK_LEGS = [
    (((6, -2, 0), (16, 2, 0)), ((9, 2, 0), (19, -2, 0)), 0),
    (((6, 1, 2), (16, 0, 0)), ((9, 0, 0), (19, 1, 2)), 1),
    (((6, 2, 0), (16, -2, 0)), ((9, -2, 0), (19, 2, 0)), 0),
    (((6, 0, 0), (16, 1, 2)), ((9, 1, 2), (19, 0, 0)), 1),
]
STAND_NEAR = ((6, 0, 0), (16, 0, 0))
STAND_FAR = ((9, 0, 0), (19, 0, 0))

# Взгляд: (gx, gy) — куда сдвинуты глаза; gx вперёд по морде, gy вниз. Кадр листа look = (gy + 1) * 3 + gx + 1.
GAZES = [(gx, gy) for gy in (-1, 0, 1) for gx in (-1, 0, 1)]

# Висит за шкирку: тело поднято, лапы вытянуты вниз и болтаются (ближние, дальние).
HANG_LEGS = [
    (((6, -1, 0), (16, 1, 1)), ((9, 1, 1), (19, -1, 0))),
    (((6, 0, 1), (16, 2, 0)), ((9, -1, 0), (19, 0, 1))),
    (((6, 1, 0), (16, -1, 1)), ((9, -1, 1), (19, 1, 0))),
    (((6, 0, 1), (16, -2, 0)), ((9, 1, 0), (19, 0, 1))),
]
HANG_BOB = 2

# Спит: лёг (тело опущено на 4 пикселя, лапы спрятаны под ним) и дышит — тело то чуть выше, то ниже.
SLEEP_BOBS = [-4, -4, -3, -3]


def zzz(sprite, frame):
    """Две буквы «z» (5×5 пикселей) всплывают над головой, по ступеньке за кадр; вторая отстаёт на полцикла."""
    path = [(31, 11), (34, 8), (37, 5), (40, 2)]
    for phase in (frame % 4, (frame + 2) % 4):
        x, y = path[phase]
        z = Layer((255, 255, 255, 255))
        for dx in range(5):
            z.rect((x + dx) / 1.5, y / 1.5, (x + dx + 1) / 1.5 - 1, (y + 1) / 1.5 - 1)
            z.rect((x + dx) / 1.5, (y + 4) / 1.5, (x + dx + 1) / 1.5 - 1, (y + 5) / 1.5 - 1)
        for d in (1, 2, 3):
            z.rect((x + 4 - d) / 1.5, (y + d) / 1.5, (x + 5 - d) / 1.5 - 1, (y + d + 1) / 1.5 - 1)
        sprite.draw(z)


# Сидит: видны только передние лапы, задние спрятаны в «окорочке».
SIT_NEAR = ((16, 0, 0, 24),)
SIT_FAR = ((19, 0, 0, 24),)
SIT_HEAD = -3

# Потягивается: зад кверху, передние лапы вытянуты вперёд, голова опущена.
STRETCH_NEAR = ((6, 0, 0, 20), (17, 4, 0, 24))
STRETCH_FAR = ((9, 0, 0, 20), (20, 4, 0, 24))
STRETCH_HEAD = 4

# Удар лапкой: ближняя передняя лапа поднята отдельным «рукавом» (центры блоков 2×2), задние стоят.
SWIPE_NEAR = ((6, 0, 0),)
SWIPES = [
    [(18, 22), (20, 22), (22, 22), (24, 21)],
    [(18, 22), (20, 22), (22, 21), (24, 20), (26, 19), (28, 18)],
]

# Балансирует на краю: передние лапы машут в разные стороны.
BALANCE = [
    (((6, 0, 0), (16, 3, 4)), ((9, 0, 0), (19, -2, 3))),
    (((6, 0, 0), (16, -2, 3)), ((9, 0, 0), (19, 3, 4))),
]


# Танец: переступает передними лапами и подпрыгивает в такт (ближние, дальние, bob).
DANCE = [
    (((6, 0, 0), (16, 0, 0)), ((9, 0, 0), (19, 0, 0)), 0),
    (((6, 0, 0), (16, 2, 3)), ((9, 0, 0), (19, 0, 0)), 1),
    (((6, 0, 0), (16, 0, 0)), ((9, 0, 0), (19, 0, 0)), 0),
    (((6, 0, 0), (16, 0, 0)), ((9, 0, 0), (19, 2, 3)), 1),
]
# Позирует: сидит и машет поднятой лапкой у мордочки.
WAVES = [
    [(16, 22), (15, 20), (15, 18), (15, 16), (15, 14)],
    [(16, 22), (15, 20), (14, 18), (13, 16), (12, 14)],
]


# По делам: присел, хвост трубой, тужится (тело подрагивает).
SQUAT = (((6, -2, 0), (16, 2, 0)), ((9, -2, 0), (19, 2, 0)))
# Закапывает: голова вниз, передние лапы по очереди гребут землю (ближние, дальние).
DIG = [
    (((6, 0, 0), (16, 2, 2)), ((9, 0, 0), (19, -1, 0))),
    (((6, 0, 0), (16, -1, 0)), ((9, 0, 0), (19, 2, 2))),
]


# Присед после приземления: лапы расставлены, тело опущено (ближние, дальние, bob).
CROUCH = [
    (((6, -2, 0), (16, 2, 0)), ((9, -2, 0), (19, 2, 0)), -2),
    (((6, -1, 0), (16, 1, 0)), ((9, -1, 0), (19, 1, 0)), -1),
]


def tint(c, k):
    """Светлее (k > 1) или темнее (k < 1), прозрачность та же."""
    return tuple(min(255, round(v * k)) for v in c[:3]) + (c[3],)


def rim(c):
    """Цвет обводки: глубокая тень заливки, наполовину к общей тёмной обводке."""
    return tuple(round(v * 0.45 * 0.5 + o * 0.5) for v, o in zip(c[:3], OUTLINE[:3])) + (255,)


def _area(x0, y0, x1, y1):
    """Пиксели, которые могут попасть в прямоугольник клеток [x0, x1) × [y0, y1)."""
    for py in range(floor(y0 * S) - 1, ceil(y1 * S) + 1):
        for px in range(floor(x0 * S) - 1, ceil(x1 * S) + 1):
            yield px, py, (px + 0.5) / S, (py + 0.5) / S


class Layer:
    """Силуэт: координаты фигур — в клетках (дробные можно), заливка — в пикселях. Обводка строится по краю."""

    def __init__(self, color):
        self.color = color
        self.px = {}

    def set(self, x, y, c=None):
        """Один пиксель."""
        self.px[(x, y)] = c or self.color

    def cell(self, x, y, c=None):
        """Одна клетка разметки."""
        self.rect(x, y, x, y, c)

    def rect(self, x0, y0, x1, y1, c=None):
        """Клетки x0..x1, y0..y1 включительно."""
        for px, py, u, v in _area(x0, y0, x1 + 1, y1 + 1):
            if x0 <= u < x1 + 1 and y0 <= v < y1 + 1:
                self.set(px, py, c)

    def rrect(self, x0, y0, x1, y1, r=1, c=None):
        """Прямоугольник клеток x0..x1, y0..y1 со скруглёнными углами радиуса r клеток."""
        X0, Y0, X1, Y1 = x0, y0, x1 + 1, y1 + 1
        for px, py, u, v in _area(X0, Y0, X1, Y1):
            if not (X0 <= u < X1 and Y0 <= v < Y1):
                continue
            cx, cy = min(max(u, X0 + r), X1 - r), min(max(v, Y0 + r), Y1 - r)
            if (u - cx) ** 2 + (v - cy) ** 2 <= r * r:
                self.set(px, py, c)

    def disc(self, cx, cy, r, c=None):
        """Круг: центр и радиус в клетках."""
        for px, py, u, v in _area(cx - r, cy - r, cx + r, cy + r):
            if (u - cx) ** 2 + (v - cy) ** 2 <= r * r:
                self.set(px, py, c)

    def blobs(self, points, size=2, c=None):
        """Цепочка кружков — хвост, поднятая лапа. Точки — левые верхние клетки блоков size×size."""
        for x, y in points:
            self.disc(x + size / 2, y + size / 2, size * 0.62, c)

    def poly(self, points, c=None):
        """Многоугольник по вершинам в клетках — острые ушки."""
        xs, ys = [p[0] for p in points], [p[1] for p in points]
        for px, py, u, v in _area(min(xs), min(ys), max(xs), max(ys)):
            inside = False
            for (ax, ay), (bx, by) in zip(points, points[1:] + points[:1]):
                if (ay > v) != (by > v) and u < ax + (v - ay) * (bx - ax) / (by - ay):
                    inside = not inside
            if inside:
                self.set(px, py, c)


def sitting_body(layer):
    """Единый грушевидный силуэт: плавная спина от шеи к тазу, без ступеньки."""
    curves = [
        ((19, 15), (14, 15), (5.5, 22), (5.5, 27)),
        ((5.5, 27), (5.5, 30), (8, 31), (12, 31)),
        ((12, 31), (16, 31), (19, 29), (21, 27)),
        ((21, 27), (22, 23), (22, 19), (22, 17)),
        ((22, 17), (22, 15.5), (20.5, 15), (19, 15)),
    ]
    points = []
    for a, b, c, d in curves:
        for step in range(20):
            t = step / 20
            points.append(tuple((1-t)**3*a[i] + 3*(1-t)**2*t*b[i]
                                + 3*(1-t)*t*t*c[i] + t**3*d[i] for i in (0, 1)))
    layer.poly(points)


def legs(layer, specs, top):
    """Несколько лап: (x, dx, lift) или (x, dx, lift, свой верх). Возвращает пиксели стоп."""
    return [p for x, dx, lift, *own in specs for p in leg(layer, x, own[0] if own else top, dx, lift)]


def leg(layer, x, top, dx=0, lift=0):
    """Лапа шириной 3 клетки: ровная полоса от верха до стопы. dx — вынос стопы, lift — насколько поднята.
    Возвращает пиксели стопы (нижняя клетка)."""
    y0, y1 = top, GROUND - lift + 1
    paw = []
    for px, py, u, v in _area(min(x, x + dx), y0, max(x, x + dx) + 3, y1):
        if not y0 <= v < y1:
            continue
        left = x + dx * (v - y0) / (y1 - y0)
        if left <= u < left + 3:
            layer.set(px, py)
            if v >= y1 - 1:
                paw.append((px, py))
    return paw


class Sprite:
    def __init__(self, w=SIZE, h=SIZE):
        self.img = Image.new("RGBA", (w, h), (0, 0, 0, 0))

    def put(self, x, y, c):
        """Один пиксель."""
        if 0 <= x < self.img.width and 0 <= y < self.img.height:
            self.img.putpixel((x, y), c)

    def cell(self, x, y, c):
        """Одна клетка разметки — пятна, полоски, ошейник."""
        for px, py, u, v in _area(x, y, x + 1, y + 1):
            if x <= u < x + 1 and y <= v < y + 1:
                self.put(px, py, c)

    def dots(self, points, c, dx=0, dy=0):
        """Пиксели списком, со сдвигом."""
        for x, y in points:
            self.put(x + dx, y + dy, c)

    def details(self, points, c, dx=0, dy=0):
        """Разметка мимики 48×48, независимая от разрешения текстуры."""
        draw = ImageDraw.Draw(self.img)
        for x, y in points:
            draw.rectangle((round((x + dx) * FACE_SCALE), round((y + dy) * FACE_SCALE),
                            round((x + dx + 1) * FACE_SCALE) - 1,
                            round((y + dy + 1) * FACE_SCALE) - 1), fill=c)

    def line(self, points, c, width=0.25):
        """Тонкая линия в клетках позы, без масштабирования готовых пикселей."""
        ImageDraw.Draw(self.img).line([(round(x * S), round(y * S)) for x, y in points],
                                     fill=c, width=max(1, round(width * S)), joint="curve")

    def oval(self, box, c):
        ImageDraw.Draw(self.img).ellipse(tuple(round(v * S) for v in box), fill=c)

    def paws(self, points, c):
        self.dots(points, c)
        # Две короткие бороздки на каждой видимой стопе.
        rows = {}
        for x, y in points:
            rows.setdefault(y, []).append(x)
        if not rows:
            return
        bottom = max(rows)
        xs = sorted(rows[bottom])
        groups = []
        for x in xs:
            if not groups or x > groups[-1][-1] + 1:
                groups.append([])
            groups[-1].append(x)
        for group in groups:
            for fraction in (0.33, 0.67):
                x = group[min(len(group) - 1, round((len(group) - 1) * fraction))]
                for y in (bottom - 1, bottom):
                    if (x, y) in points:
                        self.put(x, y, tint(c, 0.7))

    def draw(self, layer, outline=True):
        """Цветная обводка, ступенчатый свет, контактная тень и короткие пряди шерсти."""
        px = layer.px
        if not px:
            return
        min_x = min(x for x, _ in px)
        min_y = min(y for _, y in px)
        max_y = max(y for _, y in px)
        edge = max(1, round(S * 0.45))
        if outline:
            for (x, y), c in px.items():
                for distance in range(1, edge + 1):
                    for nx, ny in ((x + distance, y), (x - distance, y), (x, y + distance), (x, y - distance)):
                        if (nx, ny) not in px:
                            self.put(nx, ny, rim(c))
        for (x, y), c in px.items():
            if outline:
                # Ступенчатая палитра сохраняет пиксельный характер и даёт объём.
                height = (y - min_y) / max(1, max_y - min_y)
                k = (1.10, 1.04, 1.0, 0.96, 0.90)[min(4, int(height * 5))]
                if (x, y - edge) not in px:
                    k = 1.18
                elif (x, y + edge * 2) not in px:
                    k = 0.81
                # Редкие короткие пряди привязаны к слою, поэтому не мерцают при подскоке.
                u, v = x - min_x, y - min_y
                if c[0] > c[1] > c[2] and (u % 13 in (3, 4) and v % 11 in (4, 5, 6)):
                    k *= 1.06 if (u // 13 + v // 11) % 2 else 0.94
                c = tint(c, k)
            self.put(x, y, c)


def save_sheet(frames, path):
    w, h = frames[0].img.size
    sheet = Image.new("RGBA", (w * len(frames), h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        sheet.paste(f.img, (i * w, 0))
    sheet.save(path)


def _on_bg(img, bg, scale):
    base = Image.new("RGBA", img.size, bg)
    base.alpha_composite(img)
    return base.resize((img.width * scale, img.height * scale), Image.NEAREST).convert("RGB")


def save_gif(frames, path, ms=150, scale=3, bg=(244, 239, 230, 255)):
    imgs = [_on_bg(f.img, bg, scale) for f in frames]
    imgs[0].save(path, save_all=True, append_images=imgs[1:], duration=ms, loop=0, disposal=2)


def save_board(rows, path, scale=1, bg=(244, 239, 230, 255), gap=8):
    """Статичная доска: каждая строка — анимация, кадры слева направо."""
    w, h = rows[0][0].img.size
    cols = max(len(r) for r in rows)
    board = Image.new("RGBA", ((w + gap) * cols + gap, (h + gap) * len(rows) + gap), bg)
    for j, row in enumerate(rows):
        for i, f in enumerate(row):
            board.alpha_composite(f.img, (gap + i * (w + gap), gap + j * (h + gap)))
    board.resize((board.width * scale, board.height * scale), Image.NEAREST).save(path)


def save_scene(walk, idle, path, width=384, step=5, ms=140, scale=2, bg=(244, 239, 230, 255)):
    """Питомец идёт вправо, стоит, идёт обратно — проверка движения и зеркалирования."""
    w, h = walk[0].img.size
    shots = []  # (кадр, x, смотрит влево)
    x, i = 0, 0
    while x < width - w:
        shots.append((walk[i % len(walk)].img, x, False)); x += step; i += 1
    for k in range(8):
        shots.append((idle[k % len(idle)].img, x, False))
    while x > 0:
        shots.append((walk[i % len(walk)].img, x, True)); x -= step; i += 1
    out = []
    for img, x, left in shots:
        canvas = Image.new("RGBA", (width, h), bg)
        canvas.alpha_composite(ImageOps.mirror(img) if left else img, (x, 0))
        out.append(canvas.resize((width * scale, h * scale), Image.NEAREST).convert("RGB"))
    out[0].save(path, save_all=True, append_images=out[1:], duration=ms, loop=0)


def export(name, anims):
    """anims: {имя: (кадры, мс на кадр)}. Спрайт-листы в sprites/, превью в preview/."""
    from pathlib import Path

    root = Path(__file__).resolve().parent.parent
    (root / "sprites").mkdir(exist_ok=True)
    (root / "preview").mkdir(exist_ok=True)
    for anim, (frames, ms) in anims.items():
        save_sheet(frames, root / "sprites" / f"{name}_{anim}.png")
        save_gif(frames, root / "preview" / f"{name}_{anim}.gif", ms=ms)
    save_board([f for f, _ in anims.values()], root / "preview" / f"{name}_board.png")
    save_scene(anims["walk"][0], anims["idle"][0], root / "preview" / f"{name}_scene.gif")
