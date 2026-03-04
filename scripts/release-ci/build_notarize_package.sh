#!/usr/bin/env bash

set -euo pipefail

PROJECT_DIR="${PROJECT_DIR:-$(pwd)}"
DIST_DIR="${DIST_DIR:-$PROJECT_DIR/dist}"
BUILD_DIR="${BUILD_DIR:-$PROJECT_DIR/build}"
VERSION="${RELEASE_VERSION:-}"

SIGNING_IDENTITY="${MIAOYAN_SIGNING_IDENTITY:-}"
TEAM_ID="${MIAOYAN_TEAM_ID:-}"

NOTARY_KEY_ID="${MIAOYAN_NOTARY_KEY_ID:-}"
NOTARY_ISSUER_ID="${MIAOYAN_NOTARY_ISSUER_ID:-}"
NOTARY_API_KEY_P8="${MIAOYAN_NOTARY_API_KEY_P8:-}"
NOTARY_APPLE_ID="${MIAOYAN_NOTARY_APPLE_ID:-}"
NOTARY_PASSWORD="${MIAOYAN_NOTARY_PASSWORD:-}"

SPARKLE_PRIVATE_KEY_BASE64="${MIAOYAN_SPARKLE_PRIVATE_KEY_BASE64:-}"

if [[ -z "$VERSION" ]]; then
  VERSION="$(
    grep "MARKETING_VERSION" "$PROJECT_DIR/MiaoYan.xcodeproj/project.pbxproj" \
      | head -1 \
      | sed 's/.*= \(.*\);/\1/' \
      | tr -d ' '
  )"
fi

if [[ -z "$VERSION" ]]; then
  echo "Could not determine release version." >&2
  exit 1
fi

if [[ -z "$SIGNING_IDENTITY" || -z "$TEAM_ID" ]]; then
  echo "MIAOYAN_SIGNING_IDENTITY and MIAOYAN_TEAM_ID are required." >&2
  exit 1
fi

if [[ -z "$SPARKLE_PRIVATE_KEY_BASE64" ]]; then
  echo "MIAOYAN_SPARKLE_PRIVATE_KEY_BASE64 is required." >&2
  exit 1
fi

base64_decode() {
  if base64 --help 2>&1 | grep -q -- '--decode'; then
    base64 --decode
  else
    base64 -D
  fi
}

cd "$PROJECT_DIR"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "Building MiaoYan v${VERSION}"

xcodebuild clean -scheme MiaoYan -configuration Release >/dev/null 2>&1 || true

xcodebuild archive \
  -scheme MiaoYan \
  -configuration Release \
  -archivePath "$BUILD_DIR/MiaoYan.xcarchive" \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGNING_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  OTHER_CODE_SIGN_FLAGS="--timestamp --options runtime"

APP_PATH="$BUILD_DIR/Release/MiaoYan.app"
mkdir -p "$BUILD_DIR/Release"
cp -R "$BUILD_DIR/MiaoYan.xcarchive/Products/Applications/MiaoYan.app" "$APP_PATH"

SPARKLE_FRAMEWORK="$APP_PATH/Contents/Frameworks/Sparkle.framework"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  UPDATER_APP="$SPARKLE_FRAMEWORK/Versions/B/Updater.app"
  AUTOUPDATE_BIN="$SPARKLE_FRAMEWORK/Versions/B/Autoupdate"
  XPC_DIR="$SPARKLE_FRAMEWORK/Versions/B/XPCServices"

  [[ -d "$UPDATER_APP" ]] && codesign --force --deep --timestamp --options runtime -s "$SIGNING_IDENTITY" "$UPDATER_APP" || true
  [[ -f "$AUTOUPDATE_BIN" ]] && codesign --force --timestamp --options runtime -s "$SIGNING_IDENTITY" "$AUTOUPDATE_BIN" || true
  if [[ -d "$XPC_DIR" ]]; then
    find "$XPC_DIR" -name "*.xpc" -print0 | while IFS= read -r -d '' xpc; do
      codesign --force --deep --timestamp --options runtime -s "$SIGNING_IDENTITY" "$xpc" || true
    done
  fi
  codesign --force --deep --timestamp --options runtime -s "$SIGNING_IDENTITY" "$SPARKLE_FRAMEWORK" || true
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"

NOTARY_ZIP="$BUILD_DIR/MiaoYan_for_notary.zip"
ditto -c -k --keepParent "$APP_PATH" "$NOTARY_ZIP"

NOTARY_OUTPUT_FILE="$BUILD_DIR/notary-submit.log"
if [[ -n "$NOTARY_KEY_ID" && -n "$NOTARY_ISSUER_ID" && -n "$NOTARY_API_KEY_P8" ]]; then
  NOTARY_KEY_FILE="$BUILD_DIR/AuthKey.p8"
  printf '%s' "$NOTARY_API_KEY_P8" | base64_decode >"$NOTARY_KEY_FILE"
  xcrun notarytool submit "$NOTARY_ZIP" \
    --key "$NOTARY_KEY_FILE" \
    --key-id "$NOTARY_KEY_ID" \
    --issuer "$NOTARY_ISSUER_ID" \
    --wait | tee "$NOTARY_OUTPUT_FILE"
elif [[ -n "$NOTARY_APPLE_ID" && -n "$NOTARY_PASSWORD" && -n "$TEAM_ID" ]]; then
  xcrun notarytool submit "$NOTARY_ZIP" \
    --apple-id "$NOTARY_APPLE_ID" \
    --team-id "$TEAM_ID" \
    --password "$NOTARY_PASSWORD" \
    --wait | tee "$NOTARY_OUTPUT_FILE"
else
  echo "Notary credentials missing. Provide API key credentials or Apple ID credentials." >&2
  exit 1
fi

if ! grep -q "status: Accepted" "$NOTARY_OUTPUT_FILE"; then
  echo "Notarization failed." >&2
  cat "$NOTARY_OUTPUT_FILE" >&2
  exit 1
fi

xcrun stapler staple "$APP_PATH"

ZIP_PATH="$DIST_DIR/MiaoYan_V${VERSION}.zip"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

STAGING_DIR="$BUILD_DIR/dmg_staging"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/MiaoYan.app"
ln -s /Applications "$STAGING_DIR/Applications"

DMG_PATH="$DIST_DIR/MiaoYan_v${VERSION}.dmg"
hdiutil create -volname "MiaoYan" -srcfolder "$STAGING_DIR" -ov -format UDZO "$DMG_PATH"
xcrun stapler staple "$DMG_PATH" || true
rm -rf "$STAGING_DIR"

SIGN_UPDATE="$(
  find "$HOME/Library/Developer/Xcode/DerivedData" \
    -path "*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update" \
    -type f \
    2>/dev/null \
    | head -1
)"

if [[ -z "$SIGN_UPDATE" || ! -x "$SIGN_UPDATE" ]]; then
  echo "Sparkle sign_update tool not found." >&2
  exit 1
fi

SPARKLE_KEY_FILE="$BUILD_DIR/sparkle_private.key"
printf '%s' "$SPARKLE_PRIVATE_KEY_BASE64" | base64_decode >"$SPARKLE_KEY_FILE"

SPARKLE_OUTPUT="$(
  base64 <"$SPARKLE_KEY_FILE" | "$SIGN_UPDATE" --ed-key-file - "$ZIP_PATH"
)"
SPARKLE_SIGNATURE="$(echo "$SPARKLE_OUTPUT" | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')"

if [[ -z "$SPARKLE_SIGNATURE" ]]; then
  echo "Failed to parse Sparkle signature." >&2
  echo "$SPARKLE_OUTPUT" >&2
  exit 1
fi

ZIP_SIZE="$(stat -f%z "$ZIP_PATH")"
PUB_DATE="$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")"
DMG_SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

jq -n \
  --arg version "$VERSION" \
  --arg dmg_path "$DMG_PATH" \
  --arg zip_path "$ZIP_PATH" \
  --arg sparkle_signature "$SPARKLE_SIGNATURE" \
  --arg pub_date "$PUB_DATE" \
  --arg dmg_sha256 "$DMG_SHA256" \
  --argjson zip_length "$ZIP_SIZE" \
  '{
    version: $version,
    dmg_path: $dmg_path,
    zip_path: $zip_path,
    sparkle_signature: $sparkle_signature,
    zip_length: $zip_length,
    pub_date: $pub_date,
    dmg_sha256: $dmg_sha256
  }' >"$DIST_DIR/release-metadata.json"

echo "Build artifacts:"
echo "  $DMG_PATH"
echo "  $ZIP_PATH"
echo "  $DIST_DIR/release-metadata.json"
