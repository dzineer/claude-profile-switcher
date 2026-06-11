#!/bin/bash
set -euo pipefail

APP_NAME="Claude Profile Switcher"
PROJECT_DIR="ClaudeProfileSwitcher"
BUILD_DIR="$PROJECT_DIR/.build"
APP_BUNDLE="/Applications/$APP_NAME.app"

echo "=== Claude Profile Switcher — Build & Install ==="
echo ""

# ---- 1. Build with SwiftPM ----
echo "▸ Building with SwiftPM (release)..."
cd "$PROJECT_DIR"
swift build -c release --disable-sandbox 2>&1 | tail -3
cd ..
echo "  ✓ Build complete"
echo ""

# ---- 2. Locate the binary ----
BINARY="$BUILD_DIR/release/ClaudeProfileSwitcher"
if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi
echo "▸ Binary: $BINARY"

# ---- 3. Create .app bundle ----
echo "▸ Creating .app bundle..."
rm -rf "$APP_BUNDLE"

APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"

mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"

cp "$BINARY" "$APP_MACOS/$APP_NAME"

# ---- 4. Info.plist ----
cat > "$APP_CONTENTS/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>com.claude-profileswitcher</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleVersion</key>
    <string>1.0.0</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>12.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSUIElement</key>
    <false/>
    <key>NSHumanReadableCopyright</key>
    <string>Free to share and modify.</string>
</dict>
</plist>
PLIST
echo "  ✓ Bundle structure created"

# ---- 5. Ad-hoc sign ----
echo "▸ Ad-hoc signing (free, no developer account needed)..."
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null
echo "  ✓ Signed (ad-hoc)"

# ---- 6. Verify ----
echo ""
echo "=== Verification ==="
echo "▸ Bundle structure:"
ls -R "$APP_BUNDLE/Contents/" | head -10
echo ""
echo "▸ Signing status:"
codesign -dvv "$APP_BUNDLE" 2>&1 | grep -E "Authority|Signed|Sealed|Identifier" || echo "  (ad-hoc signature — no authority)"
echo ""
echo "▸ Disk usage:"
du -sh "$APP_BUNDLE"
echo ""

echo "=== ✓ Installed to $APP_BUNDLE ==="
echo ""
echo "To launch: open \"$APP_BUNDLE\""
echo "On first run: right-click → Open (Gatekeeper bypass, once)"
echo ""
echo "To uninstall: rm -rf \"$APP_BUNDLE\""
