#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  update_appcast.sh \
    --appcast appcast.xml \
    --notes build/release-content.json \
    --version 2.8.0 \
    --pub-date "Wed, 04 Mar 2026 10:00:00 +0000" \
    --signature "<sparkle signature>" \
    --length 12345 \
    --zip-url "https://miaoyan.app/Release/MiaoYan_V2.8.0.zip"
EOF
}

APPCAST=""
NOTES=""
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

[[ -z "$APPCAST" || -z "$NOTES" || -z "$VERSION" || -z "$PUB_DATE" || -z "$SIGNATURE" || -z "$LENGTH" || -z "$ZIP_URL" ]] && {
  usage
  exit 1
}

monster="$(jq -r '.monster_name' "$NOTES")"
emoji="$(jq -r '.emoji' "$NOTES")"

sanitize_cdata() {
  printf '%s' "$1" | sed 's/]]>/]]]]><![CDATA[>/g'
}

item_file="$(mktemp)"
{
  echo "    <item>"
  echo "      <title>${VERSION}</title>"
  echo "      <link>https://github.com/tw93/MiaoYan/releases</link>"
  echo "      <description><![CDATA["
  printf '      <h3>%s %s</h3>\n' "$(sanitize_cdata "$monster")" "$(sanitize_cdata "$emoji")"
  echo "      <ol>"
  while IFS=$'\t' read -r title description; do
    printf '        <li><strong>%s</strong>：%s</li>\n' "$(sanitize_cdata "$title")" "$(sanitize_cdata "$description")"
  done < <(jq -r '.highlights_zh[] | [.title, .description] | @tsv' "$NOTES")
  echo "      </ol>"
  printf '      <h3>%s %s</h3>\n' "$(sanitize_cdata "$monster")" "$(sanitize_cdata "$emoji")"
  echo "      <ol>"
  while IFS=$'\t' read -r title description; do
    printf '        <li><strong>%s</strong>: %s</li>\n' "$(sanitize_cdata "$title")" "$(sanitize_cdata "$description")"
  done < <(jq -r '.highlights_en[] | [.title, .description] | @tsv' "$NOTES")
  echo "      </ol>"
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
