#!/bin/bash
# MiaoYan Release Build Script - Build unsigned version

set -e

EXTERNAL_SCRIPT="$HOME/.config/miaoyan/build.sh"
if [ -x "$EXTERNAL_SCRIPT" ]; then
  exec "$EXTERNAL_SCRIPT" "$@"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Auto-detect version from project.pbxproj
VERSION=$(grep "MARKETING_VERSION" MiaoYan.xcodeproj/project.pbxproj | head -1 | sed 's/.*= \(.*\);/\1/' | tr -d ' ')
[ -n "$1" ] && VERSION="$1"
KEY_PATH="${SPARKLE_PRIVATE_KEY:-}"

if [ -z "$VERSION" ]; then
	echo -e "${RED}ERROR: Could not detect version${NC}"
	exit 1
fi

echo ""
echo "Building MiaoYan v$VERSION (unsigned)"
echo "======================================"

# 1. Clean
echo "[1/6] Cleaning..."
rm -rf ./build
xcodebuild clean -scheme MiaoYan -configuration Release 2>/dev/null || true

# 2. Archive
echo "[2/6] Archiving..."
xcodebuild archive \
	-scheme MiaoYan \
	-configuration Release \
	-archivePath "./build/MiaoYan.xcarchive" \
	CODE_SIGN_IDENTITY="" \
	CODE_SIGNING_REQUIRED=NO \
	CODE_SIGNING_ALLOWED=NO \
	2>&1 | grep -E "(error:|ARCHIVE)" || true

[ ! -d "./build/MiaoYan.xcarchive" ] && echo -e "${RED}ERROR: Archive failed${NC}" && exit 1

# 3. Export
echo "[3/6] Exporting..."
mkdir -p "./build/Release"
cp -R "./build/MiaoYan.xcarchive/Products/Applications/MiaoYan.app" "./build/Release/MiaoYan.app"

# 4. Ad-hoc sign & package
echo "[4/6] Signing & packaging..."
# Clean attributes FIRST, then sign (otherwise signature is invalidated)
xattr -cr "./build/Release/MiaoYan.app"
# Sign frameworks explicitly first to ensure consistency
if [ -d "./build/Release/MiaoYan.app/Contents/Frameworks" ]; then
	find "./build/Release/MiaoYan.app/Contents/Frameworks" -depth -name "*.framework" -print0 | xargs -0 codesign --force --deep -s -
fi
# Sign the main application
codesign --force --deep -s - "./build/Release/MiaoYan.app"
# Verify signature
codesign -v "./build/Release/MiaoYan.app" || {
	echo "Signature verification failed"
	exit 1
}

ZIP_NAME="MiaoYan_V${VERSION}.zip"
DMG_NAME="MiaoYan.dmg"
DOWNLOADS=~/Downloads
APP_NAME="MiaoYan"
BACKGROUND_IMAGE_SOURCE="./Resources/dmg-background.png"
BACKGROUND_IMAGE_NAME="$(basename "$BACKGROUND_IMAGE_SOURCE")"

cd ./build/Release && zip -r -q "../$ZIP_NAME" MiaoYan.app && cd ../..

# Create DMG with drag-to-Applications interface using hdiutil
STAGING_DIR="./build/dmg_staging"
TEMP_DMG_PATH="./build/MiaoYan_temp.dmg"
DMG_BASE_PATH="./build/${DMG_NAME%.dmg}"

# Cleanup function to detach existing volumes
cleanup_volumes() {
	local vol_pattern="/Volumes/${APP_NAME}"
	local max_attempts=15
	local attempt=1

	while [[ $attempt -le $max_attempts ]]; do
		local mounted_devices
		mounted_devices="$(
			hdiutil info \
				| awk -v pattern="$vol_pattern" '
						$0 ~ /^\/dev\// { device=$1 }
						$0 ~ pattern { print device }
					'
		)"

		if [[ -z "$mounted_devices" ]]; then
			find /Volumes -maxdepth 1 -type d -name "${APP_NAME}*" -empty -exec rmdir {} + >/dev/null 2>&1 || true
			return 0
		fi

		echo "Detaching existing volumes (Attempt $attempt/$max_attempts)..."
		while IFS= read -r dev; do
			[[ -n "$dev" ]] && hdiutil detach "$dev" -force >/dev/null 2>&1 || true
		done <<<"$mounted_devices"
		sleep 1
		attempt=$((attempt + 1))
	done
	echo -e "${YELLOW}Warning: Failed to fully detach existing volumes.${NC}"
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

cleanup_volumes
/bin/sync

rm -rf "$STAGING_DIR" "./build/$DMG_NAME" "$TEMP_DMG_PATH"
mkdir -p "$STAGING_DIR"
cp -R "./build/Release/MiaoYan.app" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

if [[ -f "$BACKGROUND_IMAGE_SOURCE" ]]; then
	mkdir -p "$STAGING_DIR/.background"
	cp "$BACKGROUND_IMAGE_SOURCE" "$STAGING_DIR/.background/$BACKGROUND_IMAGE_NAME"
else
	echo -e "${YELLOW}Warning: DMG background image not found at $BACKGROUND_IMAGE_SOURCE; using default Finder background.${NC}"
fi

mdutil -i off "$STAGING_DIR" >/dev/null 2>&1 || true

echo "Creating DMG..."
MAX_RETRIES=3
RETRY_COUNT=0

while [[ $RETRY_COUNT -lt $MAX_RETRIES ]]; do
	if ! hdiutil create -quiet -volname "$APP_NAME" \
		-srcfolder "$STAGING_DIR" \
		-ov -format UDRW \
		"$TEMP_DMG_PATH"; then
		echo "hdiutil create failed. Retrying in 2 seconds... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
		cleanup_volumes
		sleep 2
		RETRY_COUNT=$((RETRY_COUNT + 1))
		continue
	fi

	ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$TEMP_DMG_PATH" 2>/dev/null || true)"
	DEVICE="$(echo "$ATTACH_OUTPUT" | awk '/^\/dev\// { print $1; exit }')"
	MOUNT_POINT="$(echo "$ATTACH_OUTPUT" | awk -F '\t' '/\/Volumes\// { print $NF; exit }')"

	if [[ -z "$DEVICE" || -z "$MOUNT_POINT" ]]; then
		echo "Failed to attach temporary DMG. Retrying..."
		[[ -n "$DEVICE" ]] && hdiutil detach "$DEVICE" -force >/dev/null 2>&1 || true
		cleanup_volumes
		sleep 2
		RETRY_COUNT=$((RETRY_COUNT + 1))
		continue
	fi

	if [[ -f "$STAGING_DIR/.background/$BACKGROUND_IMAGE_NAME" ]]; then
		if ! configure_dmg_layout "$(basename "$MOUNT_POINT")" "$APP_NAME" "$BACKGROUND_IMAGE_NAME"; then
			echo -e "${YELLOW}Warning: Failed to configure Finder layout for DMG.${NC}"
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

	echo "hdiutil convert failed. Retrying in 2 seconds... ($((RETRY_COUNT + 1))/$MAX_RETRIES)"
	cleanup_volumes
	sleep 2
	RETRY_COUNT=$((RETRY_COUNT + 1))
done

if [ ! -f "./build/$DMG_NAME" ]; then
	echo -e "${RED}ERROR: Failed to create DMG after retries${NC}"
	exit 1
fi

rm -rf "$STAGING_DIR" "$TEMP_DMG_PATH"
xattr -cr "./build/$DMG_NAME" "./build/$ZIP_NAME"

# 5. Sparkle signature
echo "[5/6] Signing..."
SIGN_UPDATE=$(ls -t ~/Library/Developer/Xcode/DerivedData/MiaoYan-*/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update 2>/dev/null | head -1)

if [ -n "$SIGN_UPDATE" ] && [ -x "$SIGN_UPDATE" ]; then
	if [ -n "$KEY_PATH" ] && [ -f "$KEY_PATH" ]; then
		SPARKLE_OUTPUT=$("$SIGN_UPDATE" -f "$KEY_PATH" "./build/$ZIP_NAME" 2>&1)
	else
		# Use key from Keychain (default for Sparkle 2)
		SPARKLE_OUTPUT=$("$SIGN_UPDATE" "./build/$ZIP_NAME" 2>&1)
	fi
	SIGNATURE=$(echo "$SPARKLE_OUTPUT" | grep "sparkle:edSignature" | sed 's/.*sparkle:edSignature="\([^"]*\)".*/\1/')
	ZIP_SIZE=$(stat -f%z "./build/$ZIP_NAME")
else
	echo -e "${YELLOW}sign_update not found${NC}"
	SIGNATURE=""
	ZIP_SIZE=$(stat -f%z "./build/$ZIP_NAME")
fi

mv "./build/$DMG_NAME" "$DOWNLOADS/" && mv "./build/$ZIP_NAME" "$DOWNLOADS/"

# 6. Done
echo "[6/6] Done!"
echo ""
echo -e "${GREEN}MiaoYan v$VERSION build succeeded!${NC}"
echo "  DMG: $DOWNLOADS/$DMG_NAME"
echo "  ZIP: $DOWNLOADS/$ZIP_NAME"

if [ -n "$SIGNATURE" ]; then
	echo ""
	echo "appcast.xml:"
	echo "<enclosure url=\"https://miaoyan.app/Release/$ZIP_NAME\" sparkle:shortVersionString=\"$VERSION\" sparkle:version=\"$VERSION\" sparkle:edSignature=\"$SIGNATURE\" length=\"$ZIP_SIZE\" type=\"application/octet-stream\"/>"
fi
echo ""
