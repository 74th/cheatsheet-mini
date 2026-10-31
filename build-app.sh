#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="$PWD/dist/CheatSheet Mini.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/CheatSheetMini" "$APP/Contents/MacOS/CheatSheetMini"
cp -R "$BIN_DIR/CheatSheetMini_CheatSheetMini.bundle" "$APP/Contents/Resources/"
iconutil -c icns Resources/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"
cp Info.plist "$APP/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/"
# Local unsigned development build; ad-hoc signature prevents some warnings.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
printf 'Built: %s\n' "$APP"
if [[ "${1:-}" != "--no-open" ]]; then
    open "$APP"
fi
