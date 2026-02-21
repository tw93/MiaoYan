#!/bin/bash
# Mac App Store Build Script for MiaoYan

set -e

EXTERNAL_SCRIPT="$HOME/.config/miaoyan/build-appstore.sh"
if [ -x "$EXTERNAL_SCRIPT" ]; then
  exec "$EXTERNAL_SCRIPT" "$@"
fi

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}Building MiaoYan for Mac App Store...${NC}"

echo -e "${YELLOW}Cleaning build directory...${NC}"
rm -rf build/AppStore
mkdir -p build/AppStore

xcodebuild \
  -scheme MiaoYan \
  -configuration AppStore \
  -derivedDataPath build/AppStore/DerivedData \
  -archivePath build/AppStore/MiaoYan.xcarchive \
  archive

xcodebuild \
  -exportArchive \
  -archivePath build/AppStore/MiaoYan.xcarchive \
  -exportOptionsPlist scripts/ExportOptions.plist \
  -exportPath build/AppStore/Export

echo -e "${GREEN}Build complete!${NC}"
echo "Exported app location: build/AppStore/Export/MiaoYan.app"
