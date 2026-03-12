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
APP_NAME="MiaoYan"
BACKGROUND_IMAGE_SOURCE="$PROJECT_DIR/Resources/dmg-background.png"
BACKGROUND_IMAGE_NAME="$(basename "$BACKGROUND_IMAGE_SOURCE")"

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

cleanup_volumes() {
  local volume_pattern="/Volumes/${APP_NAME}"
  local max_attempts=15
  local attempt=1

  while [[ $attempt -le $max_attempts ]]; do
    local mounted_devices
    mounted_devices="$(
      hdiutil info \
        | awk -v pattern="$volume_pattern" '
            $0 ~ /^\/dev\// { device=$1 }
            $0 ~ pattern { print device }
          '
    )"

    if [[ -z "$mounted_devices" ]]; then
      find /Volumes -maxdepth 1 -type d -name "${APP_NAME}*" -empty -exec rmdir {} + >/dev/null 2>&1 || true
      return 0
    fi

    echo "Detaching existing ${APP_NAME} volumes (attempt $attempt/$max_attempts)..."
    while IFS= read -r device; do
      [[ -n "$device" ]] && hdiutil detach "$device" -force >/dev/null 2>&1 || true
    done <<<"$mounted_devices"
    sleep 1
    attempt=$((attempt + 1))
  done

  echo "Warning: Failed to fully detach existing ${APP_NAME} volumes." >&2
}

configure_dmg_layout() {
  local disk_name="$1"
  local app_name="$2"
  local background_name="$3"

  osascript >/dev/null <<EOF
tell application "Finder"
  tell disk "${disk_name}"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {100, 100, 780, 520}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 120
    set text size of viewOptions to 14
    try
      set background picture of viewOptions to file ".background:${background_name}"
    end try
    set position of item "${app_name}.app" of container window to {190, 245}
    set position of item "Applications" of container window to {500, 245}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
}

cd "$PROJECT_DIR"
rm -rf "$BUILD_DIR" "$DIST_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "Building MiaoYan v${VERSION}"

# Skip clean to preserve Asset Catalog cache
# xcodebuild clean -scheme MiaoYan -configuration Release >/dev/null 2>&1 || true

xcodebuild archive \
  -scheme MiaoYan \
  -configuration Release \
  -destination "generic/platform=macOS" \
  -archivePath "$BUILD_DIR/MiaoYan.xcarchive" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
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
TEMP_DMG_PATH="$BUILD_DIR/MiaoYan_temp.dmg"
DMG_BASE_PATH="$DIST_DIR/MiaoYan_v${VERSION}"
DMG_PATH="${DMG_BASE_PATH}.dmg"

cleanup_volumes
rm -rf "$STAGING_DIR" "$TEMP_DMG_PATH" "$DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "$APP_PATH" "$STAGING_DIR/MiaoYan.app"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$BACKGROUND_IMAGE_SOURCE" ]]; then
  mkdir -p "$STAGING_DIR/.background"
  cp "$BACKGROUND_IMAGE_SOURCE" "$STAGING_DIR/.background/$BACKGROUND_IMAGE_NAME"
else
  echo "Warning: DMG background image not found at $BACKGROUND_IMAGE_SOURCE; using default Finder background." >&2
fi

mdutil -i off "$STAGING_DIR" >/dev/null 2>&1 || true

MAX_RETRIES=3
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
  if ! hdiutil create -quiet -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDRW \
    "$TEMP_DMG_PATH"; then
    echo "hdiutil create failed. Retrying in 2 seconds... ($((RETRY_COUNT + 1))/$MAX_RETRIES)" >&2
    cleanup_volumes
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
    continue
  fi

  ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG_PATH" 2>/dev/null || true)"
  DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/^\/dev\// { print $1; exit }')"
  MOUNT_POINT="$(echo "$ATTACH_OUTPUT" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"

  if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
    echo "Failed to attach temporary DMG. Retrying..." >&2
    [[ -n "$DEVICE" ]] && hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
    cleanup_volumes
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT + 1))
    continue
  fi

  if [[ -f "$STAGING_DIR/.background/$BACKGROUND_IMAGE_NAME" ]]; then
    if ! configure_dmg_layout "$(basename "$MOUNT_POINT")" "$APP_NAME" "$BACKGROUND_IMAGE_NAME"; then
      echo "Warning: Failed to configure Finder layout for DMG." >&2
    fi
  fi

  /bin/sync
  hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true

  if hdiutil convert -quiet "$TEMP_DMG_PATH" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -ov -o "$DMG_BASE_PATH"; then
    break
  fi

  echo "hdiutil convert failed. Retrying in 2 seconds... ($((RETRY_COUNT + 1))/$MAX_RETRIES)" >&2
  cleanup_volumes
  sleep 2
  RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [[ ! -f "$DMG_PATH" ]]; then
  echo "Failed to create DMG after retries." >&2
  exit 1
fi

xcrun stapler staple "$DMG_PATH" || true
rm -rf "$STAGING_DIR" "$TEMP_DMG_PATH"

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
