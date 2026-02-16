#!/bin/bash

# Mac App Store Build Script for MiaoYan
# Usage: ./scripts/build-appstore.sh

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Building MiaoYan for Mac App Store...${NC}"

# Check for required certificates
echo -e "${YELLOW}Checking certificates...${NC}"

# Show all available certificates
echo "Available signing identities:"
security find-identity -v -p codesigning | grep -E "Developer|Distribution" || true
echo ""

if ! security find-identity -v -p codesigning | grep -qE "Mac App Distribution|3rd Party Mac Developer Application"; then
    echo -e "${RED}Error: Mac App Distribution certificate not found${NC}"
    echo ""
    echo "To apply for Mac App Store certificates:"
    echo "1. Visit: https://developer.apple.com/account/resources/certificates/list"
    echo "2. Create CSR using existing private key:"
    echo "   openssl req -new -key ~/Save/AppleCertificates_Backup/Kaku_DevID.key \\"
    echo "     -out ~/Save/AppleCertificates_Backup/MacAppStore.csr \\"
    echo "     -subj \"/emailAddress=tw93@qq.com, CN=wei tang, C=CN\""
    echo "3. Apply for 'Mac App Distribution' certificate"
    echo "4. Apply for 'Mac Installer Distribution' certificate"
    echo "5. Download and install both certificates"
    echo ""
    echo "See APPSTORE_GUIDE.md for detailed instructions."
    exit 1
fi

if ! security find-identity -v -p codesigning | grep -qE "Mac Installer Distribution|3rd Party Mac Developer Installer"; then
    echo -e "${RED}Error: Mac Installer Distribution certificate not found${NC}"
    echo "Please download and install from Apple Developer Portal"
    echo "See APPSTORE_GUIDE.md for instructions."
    exit 1
fi

echo -e "${GREEN}✓ Mac App Distribution certificate found${NC}"
echo -e "${GREEN}✓ Mac Installer Distribution certificate found${NC}"
echo ""

# Clean build
echo -e "${YELLOW}Cleaning build directory...${NC}"
rm -rf build/AppStore
mkdir -p build/AppStore

# Build App Store version
echo -e "${YELLOW}Building App Store version...${NC}"
xcodebuild \
    -scheme MiaoYan \
    -configuration AppStore \
    -derivedDataPath build/AppStore/DerivedData \
    -archivePath build/AppStore/MiaoYan.xcarchive \
    archive

# Create export options plist
cat > build/AppStore/ExportOptions.plist << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>5EH69Y5X38</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
</dict>
</plist>
EOF

# Export app
echo -e "${YELLOW}Exporting app...${NC}"
xcodebuild \
    -exportArchive \
    -archivePath build/AppStore/MiaoYan.xcarchive \
    -exportOptionsPlist build/AppStore/ExportOptions.plist \
    -exportPath build/AppStore/Export

echo -e "${GREEN}Build complete!${NC}"
echo ""
echo "Exported app location: build/AppStore/Export/MiaoYan.app"
echo ""
echo -e "${YELLOW}To upload to App Store Connect:${NC}"
echo "1. Use Transporter app (from Mac App Store)"
echo "2. Or use: xcrun altool --upload-app --type macos --file build/AppStore/Export/MiaoYan.pkg --apiKey <YOUR_API_KEY> --apiIssuer <YOUR_ISSUER_ID>"
echo ""

# Validate the build
echo -e "${YELLOW}Validating app...${NC}"
if codesign -dv --verbose=4 build/AppStore/Export/MiaoYan.app 2>&1 | grep -qE "Authority=Mac App Distribution|Authority=3rd Party Mac Developer Application"; then
    echo -e "${GREEN}App signed with Mac App Distribution certificate ✓${NC}"
else
    echo -e "${RED}Warning: App may not be signed correctly${NC}"
fi

# Check entitlements
echo -e "${YELLOW}Checking entitlements...${NC}"
codesign -d --entitlements - build/AppStore/Export/MiaoYan.app | grep -q "app-sandbox" && echo -e "${GREEN}App Sandbox enabled ✓${NC}" || echo -e "${RED}App Sandbox NOT enabled${NC}"

echo ""
echo -e "${GREEN}Done!${NC}"
