"""Щенок с висячими ушами и красным ошейником, 48×48, смотрит вправо. Позы — в клетках разметки 32×32, мордочка — в пикселях. Запуск: python3 art/dog.py"""
from pixel import (BALANCE, CROUCH, DANCE, DIG, GAZES, HANG_BOB, HANG_LEGS, OUTLINE, SIT_FAR, SIT_HEAD, SIT_NEAR, SLEEP_BOBS,
                   SQUAT, STAND_FAR, STAND_NEAR, STRETCH_FAR, STRETCH_HEAD, STRETCH_NEAR, SWIPE_NEAR, SWIPES, WALK_LEGS,
                   WAVES, S, Layer, Sprite, export, legs, zzz)

FUR = (226, 178, 118, 255)
FUR_FAR = (190, 142, 88, 255)
EAR = (139, 92, 58, 255)
WHITE = (255, 246, 232, 255)
WHITE_FAR = (224, 206, 186, 255)
TONGUE = (238, 112, 122, 255)
BLUSH = (247, 186, 190, 255)
COLLAR = (214, 64, 69, 255)
TAG = (250, 204, 82, 255)
SHINE = (255, 255, 255, 255)
SHINE_SOFT = (255, 255, 255, 150)
THROAT = (120, 44, 52, 255)
TONGUE_LINE = (206, 84, 98, 255)
NOSE_SHINE = (118, 96, 90, 255)

CREAM = (244, 216, 176, 255)

# Кремовая грудка под ошейником в каждой позе
CHEST = {"stand": [(18, 23), (19, 23), (20, 23), (21, 23), (18, 24), (19, 24), (20, 24), (21, 24), (19, 25), (20, 25), (21, 25)],
         "sit": [(16, 20), (17, 20), (18, 20), (19, 20), (16, 21), (17, 21), (18, 21), (19, 21), (17, 22), (18, 22), (19, 22), (18, 23), (19, 23)], "stretch": []}

# Короткий хвост торчком: центры блоков 2×2 от корня к кончику. Виляет между вариантами.
TAILS = [
    [(4, 18), (3, 17), (3, 16), (3, 15)],
    [(4, 18), (4, 17), (5, 16), (6, 15)],
    [(4, 18), (3, 17), (2, 16), (1, 15)],
]
# Хвост лежит на полу, пока спит.
SLEEP_TAIL = [(4, 20), (2, 21), (1, 22), (1, 23)]
# Хвост поджат, пока держат за шкирку.
HANG_TAILS = [
    [(4, 19), (3, 21), (3, 23), (4, 24)],
    [(4, 19), (4, 21), (5, 23), (6, 24)],
]
# Сидя хвост метёт пол позади.
SIT_TAILS = [
    [(5, 27), (3, 27), (2, 26), (1, 25)],
    [(5, 27), (3, 28), (2, 28), (1, 28)],
]
# Потягиваясь, хвост торчит над поднятым задом.
STRETCH_TAIL = [(5, 14), (4, 13), (4, 12), (4, 11)]
# Чешется: задняя лапа задрана к уху и дёргается.
SCRATCH = [
    [(10, 25), (11, 23), (12, 21), (13, 19), (14, 17), (15, 15)],
    [(10, 25), (11, 23), (12, 20), (13, 18), (14, 16), (15, 13)],
]

# Пятно на спине в каждой позе
PATCH = {"stand": (9, 18), "sit": (8, 22), "stretch": (7, 15)}


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


def frame(near=STAND_NEAR, far=STAND_FAR, bob=0, tail=0, blink=False, tongue=False, gaze=(0, 0),
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
    px, py = PATCH[pose]
    for x, y in [(0, 0), (1, 0), (2, 0), (3, 0), (0, 1), (1, 1), (2, 1), (1, 2)]:
        s.cell(px + x, py + y + y0, EAR)
    tip = tail[-1]
    tail_tip = Layer(WHITE)
    tail_tip.disc(tip[0] + 1, tip[1] + 1 + y0, 0.9)
    s.draw(tail_tip, outline=False)
    s.dots(near_paws, WHITE)
    if pose == "sit":
        for x in (11, 12, 13):
            s.cell(x, 30, WHITE)  # задняя лапка из-под окорочка
    for x, y in CHEST[pose]:
        s.cell(x, y + (y0 if pose == "stand" else 0), CREAM)

    hn = oy + round(head * S)  # сдвиг головы в пикселях
    hy = hn / S
    face = Layer(FUR)
    face.rrect(17, 10 + hy, 28, 20 + hy, r=3)
    s.draw(face)
    for x in range(19, 27):
        s.cell(x, 21 + hy, COLLAR)
    tag = Layer(TAG)
    tag.disc(23, 22.6 + hy, 0.9)
    s.draw(tag)

    ears = Layer(EAR)
    ears.rrect(14.6, 10.6 + hy, 17.4, 18.2 + hy, r=1.4)  # висят по бокам головы
    ears.rrect(27.6, 10.6 + hy, 30.4, 18.2 + hy, r=1.4)
    ears.rrect(16.6, 9.8 + hy, 19, 11.8 + hy, r=0.8)
    ears.rrect(26, 9.8 + hy, 28.4, 11.8 + hy, r=0.8)
    s.draw(ears)

    muzzle = Layer(WHITE)
    muzzle.rrect(20, 16 + hy, 25, 19 + hy, r=1.3)
    s.draw(muzzle, outline=False)

    # Дальше — мордочка в пикселях; голова занимает x 25..42, y 15..30, мордочка — середина на 34
    def dots(points, c):
        s.dots(points, c, dy=hn)

    dots([(28, 24), (29, 24), (39, 24), (40, 24)], BLUSH)
    dots([(33, 24), (34, 24), (35, 24), (34, 25)], OUTLINE)
    dots([(33, 24)], NOSE_SHINE)  # блик на носу
    if mouth:
        dots([(32, 26), (33, 26), (34, 26), (35, 26), (36, 26), (31, 27), (37, 27), (31, 28), (37, 28),
              (32, 29), (33, 29), (34, 29), (35, 29), (36, 29)], OUTLINE)
        dots([(32, 27), (33, 27), (34, 27), (35, 27), (36, 27)], THROAT)
        dots([(32, 28), (33, 28), (34, 28), (35, 28), (36, 28)], TONGUE)
    else:
        dots([(34, 26), (31, 26), (37, 26), (32, 27), (33, 27), (35, 27), (36, 27)], OUTLINE)
        if tongue:
            dots([(33, 28), (34, 28), (35, 28), (33, 29), (34, 29), (35, 29), (34, 30)], TONGUE)
            dots([(34, 28)], TONGUE_LINE)
    gx, gy = gaze
    for ex, side in ((30 + gx, "left"), (36 + gx, "right")):
        kind = "happy" if eyes == "wink" and side == "right" else "open" if eyes == "wink" else eyes
        eye(s, ex, 20 + gy + hn, kind)

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
    return [frame(tail=1, tongue=True), frame(tail=2, tongue=True), frame(tail=1, blink=True), frame(tail=2)]


def walk():
    return [frame(near=n, far=f, bob=b, tail=(1, 0, 2, 0)[i], tongue=True) for i, (n, f, b) in enumerate(WALK_LEGS)]


def look():
    """Девять направлений взгляда на каждый взмах хвоста."""
    return [frame(tail=t, tongue=True, gaze=g) for t in (1, 2) for g in GAZES]


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
    return [frame(tail=SIT_TAILS[0], tongue=True, **pose), frame(tail=SIT_TAILS[1], tongue=True, **pose),
            frame(tail=SIT_TAILS[0], blink=True, **pose), frame(tail=SIT_TAILS[1], **pose)]


def groom():
    """Чешет задней лапой за ухом, жмурится от удовольствия."""
    return [frame(near=SIT_NEAR, far=SIT_FAR, pose="sit", head=SIT_HEAD, tail=SIT_TAILS[i], eyes="happy", tongue=True,
                  limb=SCRATCH[i]) for i in (0, 1)]


def stretch():
    """Потягивается, потом зевает."""
    return [frame(near=STRETCH_NEAR, far=STRETCH_FAR, pose="stretch", head=STRETCH_HEAD, tail=STRETCH_TAIL, blink=True),
            frame(tail=1, head=-1, blink=True, mouth=True)]


def swipe():
    return [frame(near=SWIPE_NEAR, tail=1, gaze=(1, -1), limb=SWIPES[i]) for i in (0, 1)]


def balance():
    return [frame(near=n, far=f, tail=(1, 2)[i], mouth=True) for i, (n, f) in enumerate(BALANCE)]


def happy():
    """Виляет хвостом изо всех сил."""
    return [frame(tail=t, eyes="happy", tongue=True) for t in (1, 0, 2, 0)]


def curl():
    """Клубочек: круглый, нос в хвост, глаза зажмурены. Центр — в середине кадра, его крутят."""
    s = Sprite()
    ball = Layer(FUR)
    ball.disc(16, 17, 8)
    ball.blobs([(6, 15)])
    s.draw(ball)
    for x, y in [(10, 19), (11, 19), (12, 19), (10, 20), (11, 20)]:
        s.cell(x, y, EAR)
    ears = Layer(EAR)
    ears.rrect(13.6, 10, 16, 16.4, r=1.2)
    ears.rrect(24, 10, 26.4, 16.4, r=1.2)
    s.draw(ears)
    muzzle = Layer(WHITE)
    muzzle.rrect(18, 14, 22, 17, r=1.2)
    s.draw(muzzle, outline=False)
    s.dots([(28, 21), (29, 21), (30, 21), (29, 22)], OUTLINE)
    for ex in (25, 32):
        eye(s, ex, 16, "closed")
    for x in range(16, 25):
        s.cell(x, 19, COLLAR)
    for x in (12, 13, 16, 17):
        s.cell(x, 23, WHITE)
    return s


def potty():
    """Присел по делам и тужится, потом закапывает."""
    near, far = SQUAT
    return [frame(near=near, far=far, bob=-2, tail=1, eyes="closed"), frame(near=near, far=far, bob=-3, tail=1, eyes="closed")] + [
        frame(near=n, far=f, bob=-1, head=2, gaze=(0, 1), tail=i) for i, (n, f) in enumerate(DIG)]


def dance():
    return [frame(near=n, far=f, bob=b, tail=(1, 0, 2, 0)[i], eyes="happy", tongue=True) for i, (n, f, b) in enumerate(DANCE)]


def pose():
    """Сидит, подмигивает и машет лапкой в камеру."""
    return [frame(near=(), far=SIT_FAR, pose="sit", head=SIT_HEAD, tail=SIT_TAILS[i], eyes="wink", tongue=True,
                  limb=WAVES[i]) for i in (0, 1)]


if __name__ == "__main__":
    export("dog", {
        "idle": (idle(), 300), "walk": (walk(), 140), "look": (look(), 300), "hang": (hang(), 120),
        "land": (land(), 100), "sleep": (sleep(), 600), "sit": (sit(), 300), "groom": (groom(), 120),
        "stretch": (stretch(), 500), "swipe": (swipe(), 120), "balance": (balance(), 150), "happy": (happy(), 90), "potty": (potty(), 200), "dance": (dance(), 180), "pose": (pose(), 250), "curl": ([curl()], 200),
    })
