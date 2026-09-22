#!/bin/zsh
set -euo pipefail

# Open-source release build. Keep this artifact stopped during daily development;
# use build_sandbox_app.sh for normal iteration. Both variants intentionally share
# Resources/AppIcon.icns so the checked-in icon remains the single source of truth.

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
OUTPUT_DIR="$PROJECT_DIR/dist"
APP_DIR="$OUTPUT_DIR/Codex Usage Alert.app"
EXPECTED_APP_DIR="$PROJECT_DIR/dist/Codex Usage Alert.app"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

if [[ "$APP_DIR" != "$EXPECTED_APP_DIR" ]]; then
  echo "拒绝清理非预期的构建目录：$APP_DIR" >&2
  exit 1
fi

swift build --package-path "$PROJECT_DIR" -c release

if [[ -d "$APP_DIR" ]]; then
  rm -rf "$APP_DIR"
fi

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Helpers" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/CodexUsageAlert" "$APP_DIR/Contents/MacOS/CodexUsageAlert"
cp "$PROJECT_DIR/.build/release/codex-usage" "$APP_DIR/Contents/Helpers/codex-usage"
cp "$PROJECT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_DIR/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR/Contents/Helpers/codex-usage"
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_DIR"
fi

codesign --verify --deep --strict --verbose=2 "$APP_DIR"
echo "$APP_DIR"
