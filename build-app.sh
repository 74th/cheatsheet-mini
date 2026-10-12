#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
swift build -c release
APP="$PWD/dist/CheatSheet Mini.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/CheatSheetMini" "$APP/Contents/MacOS/CheatSheetMini"
cp Info.plist "$APP/Contents/Info.plist"
# Local unsigned development build; ad-hoc signature prevents some warnings.
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
printf 'Built: %s\n' "$APP"
open "$APP"
