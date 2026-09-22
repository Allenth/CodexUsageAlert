#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
PROJECT_DIR="${SCRIPT_DIR:h}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_DIR/Resources/Info.plist")"
APP_DIR="$PROJECT_DIR/dist/Codex Usage Alert.app"
DMG_PATH="$PROJECT_DIR/dist/CodexUsageAlert-${VERSION}-macOS.dmg"
VOLUME_NAME="Codex Usage Alert ${VERSION}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"

if [[ "$DMG_PATH" != "$PROJECT_DIR/dist/"*.dmg ]]; then
  echo "拒绝写入非预期的 DMG 路径：$DMG_PATH" >&2
  exit 1
fi

SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-}"
if [[ -z "$SIGN_IDENTITY" ]]; then
  SIGN_IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -n 1)"
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "未找到 Developer ID Application 签名证书。" >&2
  echo "请安装证书，或通过 CODE_SIGN_IDENTITY 指定签名身份。" >&2
  exit 1
fi

echo "使用签名身份：$SIGN_IDENTITY"
CODE_SIGN_IDENTITY="$SIGN_IDENTITY" "$PROJECT_DIR/scripts/build_app.sh"

STAGING_DIR="$(mktemp -d -t codex-usage-alert-dmg.XXXXXX)"
cleanup() {
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

cp -R "$APP_DIR" "$STAGING_DIR/Codex Usage Alert.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp "$PROJECT_DIR/docs/user-guide.txt" "$STAGING_DIR/使用说明.txt"
cp "$PROJECT_DIR/LICENSE" "$STAGING_DIR/LICENSE.txt"

if [[ -f "$DMG_PATH" ]]; then
  rm -f "$DMG_PATH"
fi

hdiutil create \
  -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

codesign \
  --force \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$DMG_PATH"

codesign --verify --verbose=2 "$DMG_PATH"
hdiutil verify "$DMG_PATH"

if [[ -n "$NOTARY_PROFILE" ]]; then
  xcrun notarytool submit \
    "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "未设置 NOTARY_PROFILE：已完成 Developer ID 签名，但尚未提交 Apple 公证。"
fi

echo "$DMG_PATH"
