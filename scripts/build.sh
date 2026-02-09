#!/bin/bash
# MiaoYan Release Build Script - Build unsigned version

set -e

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
# Sign the main application (remove --options runtime to avoid Library Validation crashes with ad-hoc signatures)
codesign --force --deep -s - "./build/Release/MiaoYan.app"
# Verify signature
codesign -v "./build/Release/MiaoYan.app" || {
	echo "Signature verification failed"
	exit 1
}

ZIP_NAME="MiaoYan_V${VERSION}.zip"
DMG_NAME="MiaoYan.dmg"
DOWNLOADS=~/Downloads

cd ./build/Release && zip -r -q "../$ZIP_NAME" MiaoYan.app && cd ../..

# Create DMG with drag-to-Applications interface
create-dmg "./build/Release/MiaoYan.app" "./build/" --overwrite 2>/dev/null || true
# Rename to fixed name
mv ./build/MiaoYan*.dmg "./build/$DMG_NAME" 2>/dev/null || true
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
	echo "<enclosure url=\"https://gw.alipayobjects.com/os/k/app/$ZIP_NAME\" sparkle:shortVersionString=\"$VERSION\" sparkle:version=\"$VERSION\" sparkle:edSignature=\"$SIGNATURE\" length=\"$ZIP_SIZE\" type=\"application/octet-stream\"/>"
fi
echo ""
