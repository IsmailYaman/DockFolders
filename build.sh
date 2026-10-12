#!/bin/bash
# Bouwt DockFolders.app. Met `./build.sh install` wordt hij naar ~/Applications gekopieerd en gestart.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release

APP="build/DockFolders.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/DockFolders "$APP/Contents/MacOS/DockFolders"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key><string>en</string>
    <key>CFBundleExecutable</key><string>DockFolders</string>
    <key>CFBundleIdentifier</key><string>com.ismail.dockfolders</string>
    <key>CFBundleName</key><string>DockFolders</string>
    <key>CFBundleDisplayName</key><string>DockFolders</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>LSMinimumSystemVersion</key><string>26.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

"$APP/Contents/MacOS/DockFolders" --export-icon "$APP/Contents/Resources/AppIcon.icns"
codesign --force --sign - "$APP"
echo "Gebouwd: $APP"

if [[ "${1:-}" == "install" ]]; then
    pkill -f "Applications/DockFolders.app/" 2>/dev/null && sleep 1 || true
    mkdir -p ~/Applications
    rm -rf ~/Applications/DockFolders.app
    cp -R "$APP" ~/Applications/
    open ~/Applications/DockFolders.app
    echo "Geïnstalleerd in ~/Applications/DockFolders.app"
fi
