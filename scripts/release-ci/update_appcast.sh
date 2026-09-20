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
    --zip-url "https://github.com/tw93/MiaoYan/releases/download/V2.8.0/MiaoYan_V2.8.0.zip" \
    --description-en en.html \
    --description-zh zh.html

Sparkle picks the <description> whose xml:lang matches the running system,
so pass both and each user reads the release notes in one language instead
of a stacked bilingual list. --description-html-file still takes a single
untagged block for the old shape.
EOF
}

APPCAST=""
NOTES=""
DESCRIPTION_HTML_FILE=""
DESCRIPTION_EN_FILE=""
DESCRIPTION_ZH_FILE=""
VERSION=""
PUB_DATE=""
SIGNATURE=""
LENGTH=""
ZIP_URL=""
MIN_SYSTEM_VERSION="12.0"

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
    --description-en)
      DESCRIPTION_EN_FILE="$2"
      shift 2
      ;;
    --description-zh)
      DESCRIPTION_ZH_FILE="$2"
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

# The previous fallback here was a hardcoded 4.0 paragraph, so any release that
# forgot to pass notes silently shipped the 4.0 text to every updater. Refuse
# instead: an appcast entry with the wrong notes is worse than a failed run.
emit_description() {
  local lang="$1" file="$2"
  if [[ -n "$lang" ]]; then
    echo "      <description xml:lang=\"${lang}\"><![CDATA["
  else
    echo "      <description><![CDATA["
  fi
  sanitize_cdata "$(cat "$file")"
  printf '\n'
  echo "          ]]>      </description>"
}

if [[ -n "$DESCRIPTION_EN_FILE" || -n "$DESCRIPTION_ZH_FILE" ]]; then
  for f in "$DESCRIPTION_EN_FILE" "$DESCRIPTION_ZH_FILE"; do
    [[ -n "$f" && ! -f "$f" ]] && { echo "Error: description file not found: $f" >&2; exit 1; }
  done
elif [[ -z "$DESCRIPTION_HTML_FILE" || ! -f "$DESCRIPTION_HTML_FILE" ]]; then
  echo "Error: pass --description-en/--description-zh or --description-html-file" >&2
  exit 1
fi

item_file="$(mktemp)"
{
  echo "    <item>"
  echo "      <title>${VERSION}</title>"
  echo "      <link>https://github.com/tw93/MiaoYan/releases</link>"
  if [[ -n "$DESCRIPTION_EN_FILE" || -n "$DESCRIPTION_ZH_FILE" ]]; then
    [[ -n "$DESCRIPTION_EN_FILE" ]] && emit_description "en" "$DESCRIPTION_EN_FILE"
    [[ -n "$DESCRIPTION_ZH_FILE" ]] && emit_description "zh-Hans" "$DESCRIPTION_ZH_FILE"
  else
    emit_description "" "$DESCRIPTION_HTML_FILE"
  fi
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
