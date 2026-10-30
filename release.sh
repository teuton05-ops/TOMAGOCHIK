#!/bin/zsh
# Собрать установочный образ для GitHub Releases: ./release.sh
set -euo pipefail
cd "${0:A:h}"

./build.sh
codesign --verify --deep --strict build/Tamagochi.app

STAGING=$(mktemp -d "${TMPDIR:-/tmp}/tamagochi-release.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
chmod 755 "$STAGING"
ditto build/Tamagochi.app "$STAGING/Tamagochi.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/Установка.txt" <<'TEXT'
TOMAGOCHIK — питомец на рабочем столе
Для Mac с чипом Apple M и macOS 13 или новее.

1. Перетащите Tamagochi.app на ярлык Applications (Программы).
2. Откройте Tamagochi из папки «Программы».
3. Если macOS заблокирует запуск, откройте:
   Системные настройки → Конфиденциальность и безопасность → Всё равно открыть.
   Затем подтвердите запуск приложения.

Питомец появится на рабочем столе, а лапка — в строке меню.
Отдельного окна и значка в Dock нет. Настройки и выход — через меню лапки.
Двойной клик по питомцу создаёт напоминание.

Для прогулок по окнам включите Tamagochi в:
Системные настройки → Конфиденциальность и безопасность → Универсальный доступ.

Обновление: закройте приложение через меню лапки и замените его в «Программах».
При обновлении может потребоваться повторно выдать разрешение в настройках.

Исходники и новые версии: https://github.com/teuton05-ops/TOMAGOCHIK
TEXT

hdiutil create -volname TOMAGOCHIK -srcfolder "$STAGING" -format UDZO \
  -ov build/Tamagochi.dmg
hdiutil verify build/Tamagochi.dmg
(cd build && shasum -a 256 Tamagochi.dmg > Tamagochi.dmg.sha256)
echo "Готово: build/Tamagochi.dmg"
