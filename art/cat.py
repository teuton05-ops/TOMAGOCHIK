"""Рыжий котик, 48×48, смотрит вправо. Позы — в клетках разметки 32×32, мордочка — в пикселях. Запуск: python3 art/cat.py"""
from pixel import (BALANCE, CROUCH, DANCE, DIG, GAZES, HANG_BOB, HANG_LEGS, OUTLINE, SIT_FAR, SIT_HEAD, SIT_NEAR, SLEEP_BOBS,
                   SQUAT, STAND_FAR, STAND_NEAR, STRETCH_FAR, STRETCH_HEAD, STRETCH_NEAR, SWIPE_NEAR, SWIPES, WALK_LEGS,
                   WAVES, S, Layer, Sprite, export, legs, zzz)

FUR = (240, 160, 75, 255)
FUR_FAR = (204, 126, 56, 255)
STRIPE = (196, 112, 44, 255)
WHITE = (255, 244, 230, 255)
WHITE_FAR = (224, 204, 184, 255)
PINK = (242, 139, 154, 255)
BLUSH = (247, 186, 190, 255)
SHINE = (255, 255, 255, 255)
SHINE_SOFT = (255, 255, 255, 150)
NOSE = (214, 104, 122, 255)
THROAT = (120, 44, 52, 255)
WHISKER = (214, 196, 178, 255)

CREAM = (250, 214, 168, 255)

# Кремовая грудка под головой в каждой позе
CHEST = {"stand": [(18, 22), (19, 22), (20, 22), (21, 22), (18, 23), (19, 23), (20, 23), (21, 23), (19, 24), (20, 24), (21, 24), (20, 25), (21, 25)],
         "sit": [(16, 19), (17, 19), (18, 19), (19, 19), (16, 20), (17, 20), (18, 20), (19, 20), (17, 21), (18, 21), (19, 21), (18, 22), (19, 22)], "stretch": []}

# Хвост: центры блоков 2×2 от корня к кончику
TAILS = [
    [(4, 19), (3, 18), (2, 17), (2, 16), (2, 15), (2, 14), (3, 13)],
    [(4, 19), (3, 18), (3, 17), (3, 16), (3, 15), (4, 14), (5, 13)],
]
# Хвост лежит на полу и загибается к лапам, пока спит.
SLEEP_TAIL = [(4, 20), (2, 21), (1, 22), (1, 23), (3, 24), (5, 25)]
# Хвост повис, пока держат за шкирку: качается в две стороны.
HANG_TAILS = [
    [(4, 19), (3, 21), (2, 23), (2, 25), (2, 27), (3, 28)],
    [(4, 19), (4, 21), (4, 23), (5, 25), (6, 27), (7, 28)],
]
# Сидя хвост лежит на полу позади, кончик подрагивает.
SIT_TAILS = [
    [(5, 27), (3, 28), (2, 27), (1, 25), (1, 23)],
    [(5, 27), (3, 28), (2, 28), (1, 27), (1, 25)],
]
# Потягиваясь, хвост задран над поднятым задом.
STRETCH_TAIL = [(5, 15), (4, 13), (4, 11), (4, 9), (5, 7), (6, 6)]
# Умывается: лапа у рта, вверх-вниз.
WASH = [
    [(16, 22), (17, 20), (18, 18), (20, 17)],
    [(16, 22), (17, 21), (18, 19), (20, 18)],
]

# Где полоски на спине в каждой позе
STRIPES = {"stand": [(9, 18), (12, 18), (15, 18)], "sit": [(7, 22), (10, 21), (13, 18)], "stretch": [(7, 16), (10, 16), (14, 20)]}


def stripe(s, x, y):
    """Полоска на шерсти: клетка разметки → короткий клин в пикселях."""
    nx, ny = round(x * S), round(y * S)
    s.dots([(nx, ny), (nx + 1, ny), (nx, ny + 1), (nx + 1, ny + 1), (nx, ny + 2)], STRIPE)


def eye(s, ex, ey, kind):
    """Глаз 3×4 в пикселях: открыт (с бликами), закрыт «‿», доволен «^»."""
    if kind == "closed":
        s.dots([(ex, ey + 2), (ex + 1, ey + 3), (ex + 2, ey + 2)], OUTLINE)
    elif kind == "happy":
        s.dots([(ex - 1, ey + 3), (ex, ey + 2), (ex + 1, ey + 1), (ex + 2, ey + 2), (ex + 3, ey + 3)], OUTLINE)
    else:
        s.dots([(ex + i, ey + j) for i in range(3) for j in range(4)], OUTLINE)
        s.put(ex, ey, SHINE)
        s.put(ex + 2, ey + 2, SHINE_SOFT)


def frame(near=STAND_NEAR, far=STAND_FAR, bob=0, tail=0, blink=False, gaze=(0, 0),
          pose="stand", head=0, eyes=None, mouth=False, limb=None):
    """near/far: (x, dx, lift[, верх]) для задних и передних лап, в клетках. tail — номер из TAILS или свои точки.
    pose: stand, sit, stretch; head — сдвиг головы относительно тела; eyes: open, closed, happy, wink;
    mouth — зевает; limb — поднятая лапа поверх всего (блоки 2×2, на последнем — подушечка)."""
    tail = TAILS[tail] if isinstance(tail, int) else tail
    eyes = eyes or ("closed" if blink else "open")
    s = Sprite()
    oy = round(-bob * S)  # подскок тела в пикселях
    y0 = oy / S  # он же в клетках
    top = 23 + y0

    far_legs = Layer(FUR_FAR)
    far_paws = legs(far_legs, far, top)
    s.draw(far_legs)
    s.dots(far_paws, WHITE_FAR)

    body = Layer(FUR)
    if pose == "sit":
        body.rrect(5, 21, 14, 30, r=3.5)  # «окорочок» на полу
        body.rrect(11, 15, 20, 27, r=3)  # грудь торчком
    elif pose == "stretch":
        body.rrect(5, 14, 13, 22, r=3.5)  # зад кверху
        body.rrect(11, 18, 22, 26, r=3)  # грудь у пола
    else:
        body.rrect(5, 18 + y0, 21, 26 + y0, r=3.5)
    body.blobs([(x, y + y0) for x, y in tail])
    near_paws = legs(body, near, top)
    s.draw(body)
    for x, y in STRIPES[pose]:
        stripe(s, x, y + y0)
    for k in (-1, 3):
        x, y = tail[k]
        cx, cy = round((x + 1) * S), round((y + 1 + y0) * S)
        s.dots([(cx - 1, cy - 1), (cx, cy - 1), (cx - 1, cy), (cx, cy)], STRIPE)
    s.dots(near_paws, WHITE)
    if pose == "sit":
        for x in (11, 12, 13):
            s.cell(x, 30, WHITE)  # задняя лапка из-под окорочка
    for x, y in CHEST[pose]:
        s.cell(x, y + (y0 if pose == "stand" else 0), CREAM)

    hn = oy + round(head * S)  # сдвиг головы в пикселях
    hy = hn / S
    face = Layer(FUR)
    face.rrect(17, 11 + hy, 28, 20 + hy, r=2.4)
    face.disc(18, 18.6 + hy, 1.5)  # пушистые щёки
    face.disc(28, 18.6 + hy, 1.5)
    face.poly([(17.2, 7 + hy), (17.2, 12.6 + hy), (22.4, 12.6 + hy)])  # уши
    face.poly([(28.8, 7 + hy), (28.8, 12.6 + hy), (23.6, 12.6 + hy)])
    s.draw(face)
    inner = Layer(PINK)
    inner.poly([(18, 9.2 + hy), (18, 12.2 + hy), (20.8, 12.2 + hy)])
    inner.poly([(28, 9.2 + hy), (28, 12.2 + hy), (25.2, 12.2 + hy)])
    s.draw(inner, outline=False)

    # Дальше — мордочка в пикселях; голова занимает x 25..42, y 16..30, середина между 33 и 34
    def dots(points, c):
        s.dots(points, c, dy=hn)

    dots([(33, 17), (34, 17), (33, 18), (34, 18), (29, 17), (30, 17), (29, 18), (37, 17), (38, 17), (38, 18)], STRIPE)
    gx, gy = gaze
    for ex, side in ((28 + gx, "left"), (37 + gx, "right")):
        kind = "happy" if eyes == "wink" and side == "right" else "open" if eyes == "wink" else eyes
        eye(s, ex, 21 + gy + hn, kind)
    dots([(26, 26), (27, 26), (40, 26), (41, 26)], BLUSH)
    dots([(32, 25), (33, 25), (34, 25), (35, 25)], PINK)
    dots([(33, 26), (34, 26)], NOSE)
    if mouth:
        dots([(32, 27), (33, 27), (34, 27), (35, 27), (31, 28), (36, 28), (31, 29), (36, 29), (32, 30), (33, 30), (34, 30), (35, 30)], OUTLINE)
        dots([(32, 28), (33, 28), (34, 28), (35, 28)], THROAT)
        dots([(32, 29), (33, 29), (34, 29), (35, 29)], PINK)
    else:
        dots([(31, 29), (32, 29), (33, 29), (34, 29), (35, 29), (36, 29), (32, 30), (33, 30), (34, 30), (35, 30)], CREAM)
        dots([(31, 27), (33, 27), (34, 27), (36, 27), (32, 28), (35, 28)], OUTLINE)
    dots([(45, 26), (46, 25), (47, 25), (45, 28), (46, 28), (47, 29)], WHISKER)  # усы торчат за щёку

    if limb:
        paw = Layer(FUR)
        paw.blobs(limb)
        s.draw(paw)
        x, y = limb[-1]
        pad = Layer(WHITE)
        pad.disc(x + 1, y + 1, 1)
        s.draw(pad, outline=False)
    return s


def idle():
    return [frame(tail=0), frame(tail=1), frame(tail=0, blink=True), frame(tail=1)]


def walk():
    return [frame(near=n, far=f, bob=b, tail=i // 2) for i, (n, f, b) in enumerate(WALK_LEGS)]


def look():
    """Девять направлений взгляда на каждый взмах хвоста."""
    return [frame(tail=t, gaze=g) for t in (0, 1) for g in GAZES]


def hang():
    return [frame(near=n, far=f, bob=HANG_BOB, tail=HANG_TAILS[i // 2]) for i, (n, f) in enumerate(HANG_LEGS)]


def land():
    return [frame(near=n, far=f, bob=b, blink=b < -1) for n, f, b in CROUCH]


def sleep():
    frames = []
    for i, b in enumerate(SLEEP_BOBS):
        f = frame(bob=b, tail=SLEEP_TAIL, blink=True)
        zzz(f, i)
        frames.append(f)
    return frames


def sit():
    pose = dict(near=SIT_NEAR, far=SIT_FAR, pose="sit", head=SIT_HEAD)
    return [frame(tail=SIT_TAILS[0], **pose), frame(tail=SIT_TAILS[1], **pose),
            frame(tail=SIT_TAILS[0], blink=True, **pose), frame(tail=SIT_TAILS[1], **pose)]


def groom():
    """Умывается: сидит, лапа ходит у рта, глаза прикрыты."""
    return [frame(near=(), far=SIT_FAR, pose="sit", head=SIT_HEAD, tail=SIT_TAILS[i], eyes="happy", limb=WASH[i])
            for i in (0, 1)]


def stretch():
    """Потягивается, потом зевает."""
    return [frame(near=STRETCH_NEAR, far=STRETCH_FAR, pose="stretch", head=STRETCH_HEAD, tail=STRETCH_TAIL, blink=True),
            frame(head=-1, blink=True, mouth=True)]


def swipe():
    return [frame(near=SWIPE_NEAR, gaze=(1, -1), limb=SWIPES[i]) for i in (0, 1)]


def balance():
    return [frame(near=n, far=f, tail=i, mouth=True) for i, (n, f) in enumerate(BALANCE)]


def happy():
    return [frame(tail=0, eyes="happy"), frame(tail=1, eyes="happy")]


def curl():
    """Клубочек: круглый, нос в хвост, глаза зажмурены. Центр — в середине кадра, его крутят."""
    s = Sprite()
    ball = Layer(FUR)
    ball.disc(16, 17, 8)
    ball.poly([(16.6, 6.6), (16.6, 10.6), (20.2, 10.6)])
    ball.poly([(24.4, 6.6), (24.4, 10.6), (20.8, 10.6)])
    ball.blobs([(7, 19), (7, 21), (8, 23), (10, 24), (12, 25)])
    s.draw(ball)
    for x, y in [(10, 12), (9, 15), (10, 18)]:
        stripe(s, x, y)
    for x, y in [(12, 25), (13, 25)]:
        s.cell(x, y, STRIPE)
    s.cell(17, 8.5, PINK)
    s.cell(23, 8.5, PINK)
    for ex in (25, 33):
        eye(s, ex, 17, "closed")
    s.dots([(23, 22), (24, 22), (35, 22), (36, 22)], BLUSH)
    s.dots([(29, 22), (30, 22)], PINK)
    for x in (13, 14, 17, 18):
        s.cell(x, 23, WHITE)
    return s


def potty():
    """Присел по делам и тужится, потом закапывает."""
    near, far = SQUAT
    return [frame(near=near, far=far, bob=-2, tail=0, eyes="closed"), frame(near=near, far=far, bob=-3, tail=0, eyes="closed")] + [
        frame(near=n, far=f, bob=-1, head=2, gaze=(0, 1), tail=i) for i, (n, f) in enumerate(DIG)]


def dance():
    return [frame(near=n, far=f, bob=b, tail=i % 2, eyes="happy") for i, (n, f, b) in enumerate(DANCE)]


def pose():
    """Сидит, подмигивает и машет лапкой в камеру."""
    return [frame(near=(), far=SIT_FAR, pose="sit", head=SIT_HEAD, tail=SIT_TAILS[i], eyes="wink", limb=WAVES[i])
            for i in (0, 1)]


if __name__ == "__main__":
    export("cat", {
        "idle": (idle(), 300), "walk": (walk(), 140), "look": (look(), 300), "hang": (hang(), 120),
        "land": (land(), 100), "sleep": (sleep(), 600), "sit": (sit(), 300), "groom": (groom(), 200),
        "stretch": (stretch(), 500), "swipe": (swipe(), 120), "balance": (balance(), 150), "happy": (happy(), 250), "potty": (potty(), 200), "dance": (dance(), 180), "pose": (pose(), 250), "curl": ([curl()], 200),
    })
