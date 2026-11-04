#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Codex Usage Alert.app"

SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
swift build --package-path "$PROJECT_DIR" -c release --sdk "$SDK_PATH" \
  -Xlinker -platform_version -Xlinker macos -Xlinker 13.0 -Xlinker "$SDK_VERSION"

if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/CodexUsageAlert" "$APP_DIR/Contents/MacOS/CodexUsageAlert"
cp "$PROJECT_DIR/.build/release/codex-usage" "$APP_DIR/Contents/Helpers/codex-usage"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
xcrun actool "$PROJECT_DIR/Resources/AppIcon.icon" \
  --compile "$APP_DIR/Contents/Resources" \
  --platform macosx --minimum-deployment-target 13.0 \
  --app-icon AppIcon --output-partial-info-plist "$OUTPUT_DIR/app-icon-info.plist"
# Preserve the reviewed high-resolution legacy fallback for macOS 13–15.
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Add :DTSDKName string macosx$SDK_VERSION" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
echo "$APP_DIR"
