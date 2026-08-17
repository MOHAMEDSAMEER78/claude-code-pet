#!/bin/bash
# Builds ClaudePet.app, a minimal macOS app bundle wrapping the SPM binary.
set -euo pipefail
cd "$(dirname "$0")"

CONFIG="${1:-debug}"
swift build -c "$CONFIG"

APP="ClaudePet.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp ".build/$CONFIG/ClaudePet" "$APP/Contents/MacOS/ClaudePet"
cp "Sources/ClaudePet/Info.plist" "$APP/Contents/Info.plist"
cp "Resources/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"
# Bundled so HookInstaller can set up/repair ~/.claude/settings.json from
# inside the app itself, independent of wherever this checkout lives.
cp "hooks/pet-hook.py" "$APP/Contents/Resources/pet-hook.py"
cp "hooks/settings-snippet.json" "$APP/Contents/Resources/settings-snippet.json"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
# Nudge Launch Services / Finder to drop any cached icon for this bundle id
# so the new icon shows up immediately instead of a stale placeholder.
touch "$APP"

echo "Built $APP"
