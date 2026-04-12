#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  update_appcast.sh \
    --appcast appcast.xml \
    --version 2.8.0 \
    --pub-date "Wed, 04 Mar 2026 10:00:00 +0000" \
    --signature "<sparkle signature>" \
    --length 12345 \
    --zip-url "https://miaoyan.app/Release/MiaoYan_V2.8.0.zip"
EOF
}

APPCAST=""
NOTES=""
DESCRIPTION_HTML_FILE=""
VERSION=""
PUB_DATE=""
SIGNATURE=""
LENGTH=""
ZIP_URL=""
MIN_SYSTEM_VERSION="11.5"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --appcast)
      APPCAST="$2"
      shift 2
      ;;
    --notes)
      NOTES="$2"
      shift 2
      ;;
    --description-html-file)
      DESCRIPTION_HTML_FILE="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --pub-date)
      PUB_DATE="$2"
      shift 2
      ;;
    --signature)
      SIGNATURE="$2"
      shift 2
      ;;
    --length)
      LENGTH="$2"
      shift 2
      ;;
    --zip-url)
      ZIP_URL="$2"
      shift 2
      ;;
    --minimum-system-version)
      MIN_SYSTEM_VERSION="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

[[ -z "$APPCAST" || -z "$VERSION" || -z "$PUB_DATE" || -z "$SIGNATURE" || -z "$LENGTH" || -z "$ZIP_URL" ]] && {
  usage
  exit 1
}

sanitize_cdata() {
  printf '%s' "$1" | sed 's/]]>/]]]]><![CDATA[>/g'
}

description_body=""
if [[ -n "$DESCRIPTION_HTML_FILE" && -f "$DESCRIPTION_HTML_FILE" ]]; then
  description_body="$(cat "$DESCRIPTION_HTML_FILE")"
else
  description_body="$(printf '      <p>详细更新请查看 GitHub Release 页面。</p>\n      <p>See the GitHub release page for full release notes.</p>')"
fi

item_file="$(mktemp)"
{
  echo "    <item>"
  echo "      <title>${VERSION}</title>"
  echo "      <link>https://github.com/tw93/MiaoYan/releases</link>"
  echo "      <description><![CDATA["
  printf '%s\n' "$description_body"
  echo "          ]]>      </description>"
  echo "      <pubDate>${PUB_DATE}</pubDate>"
  echo "      <enclosure url=\"${ZIP_URL}\" sparkle:shortVersionString=\"${VERSION}\" sparkle:version=\"${VERSION}\" sparkle:edSignature=\"${SIGNATURE}\" length=\"${LENGTH}\" type=\"application/octet-stream\"/>"
  echo "      <sparkle:minimumSystemVersion>${MIN_SYSTEM_VERSION}</sparkle:minimumSystemVersion>"
  echo "    </item>"
} >"$item_file"

perl -0777 -i -pe "s@\\s*<item>\\s*<title>\\Q${VERSION}\\E</title>.*?</item>@@sg" "$APPCAST"

ITEM_CONTENT="$(cat "$item_file")"
export ITEM_CONTENT
perl -0777 -i -pe '
  BEGIN { $item = $ENV{"ITEM_CONTENT"}; }
  if (!s{(<channel>\s*<title>.*?</title>\n)(\s*)(<item>)}{$1 . $item . "\n" . $2 . $3}se) {
    die "Failed to locate appcast insertion point\n";
  }
' "$APPCAST"

rm -f "$item_file"
