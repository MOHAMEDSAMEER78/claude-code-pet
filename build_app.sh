#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="ClaudePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/$CONFIG/ClaudePet" "$APP/Contents/MacOS/ClaudePet"
cp "Sources/ClaudePet/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
cp -R ".build/$CONFIG/ClaudePet_ClaudePet.bundle" "$APP/Contents/Resources/ClaudePet_ClaudePet.bundle"
cp "hooks/pet-hook.py" "$APP/Contents/Resources/pet-hook.py"
cp "hooks/settings-snippet.json" "$APP/Contents/Resources/settings-snippet.json"
cp "hooks/pet-statusline.py" "$APP/Contents/Resources/pet-statusline.py"

cp -R ".build/$CONFIG/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ClaudePet"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
touch "$APP"

echo "Built $APP"
