#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="$PROJECT_DIR/dist-sandbox"
APP_DIR="$OUTPUT_DIR/Codex Usage Alert.app"
EXPECTED_APP_DIR="$PROJECT_DIR/dist-sandbox/Codex Usage Alert.app"

if [[ "$APP_DIR" != "$EXPECTED_APP_DIR" ]]; then
  echo "拒绝清理非预期的构建目录：$APP_DIR" >&2
  exit 1
fi

swift build --package-path "$PROJECT_DIR" -c release

if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/CodexUsageAlert" "$APP_DIR/Contents/MacOS/CodexUsageAlert"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

/usr/libexec/PlistBuddy \
  -c "Set :CFBundleIdentifier com.huijing.codex-usage-alert.sandbox-prototype" \
  -c "Set :CFBundleDisplayName Codex 用量预警 Sandbox" \
  -c "Delete :CFBundleURLTypes" \
  "$APP_DIR/Contents/Info.plist"

codesign \
  --force \
  --sign - \
  --entitlements "$PROJECT_DIR/Resources/AppStorePrototype.entitlements" \
  "$APP_DIR"

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
