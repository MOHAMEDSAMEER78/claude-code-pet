#!/bin/bash
# Builds ClaudePet.app, a minimal macOS app bundle wrapping the SPM binary.
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
# SPM generates a resource bundle for the localized strings (Localizable
# .strings) declared via `resources:` in Package.swift - Bundle.module's
# accessor looks for it next to Bundle.main, so it has to land in
# Contents/Resources or L(...) silently falls back to raw keys at runtime.
cp -R ".build/$CONFIG/ClaudePet_ClaudePet.bundle" "$APP/Contents/Resources/ClaudePet_ClaudePet.bundle"
# Bundled so HookInstaller can set up/repair ~/.claude/settings.json from
# inside the app itself, independent of wherever this checkout lives.
cp "hooks/pet-hook.py" "$APP/Contents/Resources/pet-hook.py"
cp "hooks/settings-snippet.json" "$APP/Contents/Resources/settings-snippet.json"
cp "hooks/pet-statusline.py" "$APP/Contents/Resources/pet-statusline.py"

# Sparkle is a dynamic framework (not statically linked) - it has to ship
# inside the bundle at runtime. SPM's binary only carries an @loader_path
# rpath (Contents/MacOS, where the plain executable lives) - add the
# standard app-bundle rpath so it also finds frameworks one level up, in
# Contents/Frameworks, which is where Xcode-built apps conventionally put
# them and where HookInstaller/Finder/Gatekeeper expect a bundled framework.
cp -R ".build/$CONFIG/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP/Contents/MacOS/ClaudePet"

codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true
# Nudge Launch Services / Finder to drop any cached icon for this bundle id
# so the new icon shows up immediately instead of a stale placeholder.
touch "$APP"

echo "Built $APP"
