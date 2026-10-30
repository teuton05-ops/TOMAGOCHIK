#!/bin/zsh
# Собирает build/Tamagochi.app из app/*.swift и sprites/*.png. Запуск: ./build.sh && open build/Tamagochi.app
set -euo pipefail
cd "${0:A:h}"

APP=build/Tamagochi.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources/sprites"

# Свежий SDK из Command Line Tools бывает новее компилятора — тогда берём SDK 26.
SDKS=/Library/Developer/CommandLineTools/SDKs
SDK="${SDK:-$( [[ -d $SDKS/MacOSX26.sdk ]] && echo $SDKS/MacOSX26.sdk || xcrun --show-sdk-path )}"

swiftc -O -swift-version 5 -target arm64-apple-macos13.0 -sdk "$SDK" \
  -o "$APP/Contents/MacOS/Tamagochi" app/*.swift

cp sprites/*.png "$APP/Contents/Resources/sprites/"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Тамагочи</string>
  <key>CFBundleExecutable</key><string>Tamagochi</string>
  <key>CFBundleIdentifier</key><string>local.tamagochi</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.2.0</string>
  <key>CFBundleVersion</key><string>2</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>NSDownloadsFolderUsageDescription</key><string>Чтобы держать в зубах файлы из «Загрузок» и отдавать их обратно.</string>
  <key>NSDocumentsFolderUsageDescription</key><string>Чтобы держать в зубах файлы из «Документов» и отдавать их обратно.</string>
  <key>NSDesktopFolderUsageDescription</key><string>Чтобы держать в зубах файлы с рабочего стола и отдавать их обратно.</string>
  <key>NSRemovableVolumesUsageDescription</key><string>Чтобы держать в зубах файлы с флешек и дисков и отдавать их обратно.</string>
  <key>NSLocationUsageDescription</key><string>Чтобы знать погоду за окном: в дождь я хожу под зонтиком.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Чтобы знать погоду за окном: в дождь я хожу под зонтиком.</string>
  <key>NSNetworkVolumesUsageDescription</key><string>Чтобы держать в зубах файлы с сетевых дисков и отдавать их обратно.</string>
</dict>
</plist>
PLIST

# Подписываем самоподписанным сертификатом «Tamagochi Dev» из связки ключей: с ним macOS узнаёт
# приложение по сертификату, а не по хэшу кода, и «Универсальный доступ» не слетает после пересборки.
# Без сертификата — временная подпись, тогда доступ придётся выдавать заново после каждой сборки.
IDENTITY=$(security find-identity -p codesigning | awk '/"Tamagochi Dev"/ { print $2; exit }')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Готово: $APP"
