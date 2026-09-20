#!/usr/bin/env bash
# Convert .github/RELEASE_NOTES.md to appcast <description> inner HTML.
# Usage: notes_to_html.sh [--lang en|zh] [path-to-RELEASE_NOTES.md]
# Output: HTML fragment suitable for CDATA in appcast.xml
#
# Without --lang both lists are emitted under their own <h3>, which is the
# shape a single untagged <description> needs. With --lang only that language's
# <ol> comes out and the heading is dropped, because a per-language
# <description xml:lang="..."> is already labelled by Sparkle.

set -euo pipefail

LANG_FILTER=""
NOTES_FILE=".github/RELEASE_NOTES.md"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --lang)
      LANG_FILTER="${2:-}"
      case "$LANG_FILTER" in
        en|zh) ;;
        *) echo "Error: --lang takes en or zh" >&2; exit 1 ;;
      esac
      shift 2
      ;;
    *)
      NOTES_FILE="$1"
      shift
      ;;
  esac
done

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Error: $NOTES_FILE not found" >&2
  exit 1
fi

HEADER="$(head -1 "$NOTES_FILE")"
if [[ "$HEADER" =~ ^#\ V([0-9]+\.[0-9]+\.[0-9]+)[[:space:]]*(.*)$ ]]; then
  VERSION="${BASH_REMATCH[1]}"
  MONSTER="${BASH_REMATCH[2]}"
else
  VERSION=""
  MONSTER="$HEADER"
fi
if [[ -n "$VERSION" && -z "$MONSTER" ]]; then
  MONSTER="V${VERSION}"
fi

format_item() {
  local line="$1"
  local body="${line#*. }"
  body="$(printf '%s' "$body" | sed 's/\*\*\([^*]*\)\*\*[：:][[:space:]]*/\<strong\>\1\<\/strong\>：/')"
  body="${body//\`/}"
  echo "    <li>${body}</li>"
}

if grep -q "^## Changelog" "$NOTES_FILE" || grep -q "^## 更新日志" "$NOTES_FILE"; then
  emit_section() {
    local section_header="$1"
    local in_section=0
    # Label each list by language instead of repeating the codename twice;
    # the codename already appears in the release title.
    [[ -z "$LANG_FILTER" ]] && echo "  <h3>${section_header}</h3>"
    echo "  <ol>"
    while IFS= read -r line; do
      if [[ "$line" =~ ^##[[:space:]]+"$section_header" ]]; then
        in_section=1; continue
      fi
      if [[ "$in_section" -eq 1 && "$line" =~ ^##[[:space:]] ]]; then break; fi
      if [[ "$in_section" -eq 1 && "$line" =~ ^[0-9]+\. ]]; then format_item "$line"; fi
    done <"$NOTES_FILE"
    echo "  </ol>"
  }
  case "$LANG_FILTER" in
    en) emit_section "Changelog" ;;
    zh) emit_section "更新日志" ;;
    *) emit_section "Changelog"; emit_section "更新日志" ;;
  esac
else
  # Sectionless format: two blocks separated by "^---$"
  # Block before "---" and block after "---"; emit after-block first (English), then before-block (Chinese).
  emit_block() {
    local target="$1"  # "before" or "after"
    local heading="$2"
    local in_target=0
    local past_sep=0
    # Label each list by language instead of repeating the codename twice;
    # the codename already appears in the release title.
    [[ -z "$LANG_FILTER" ]] && echo "  <h3>${heading}</h3>"
    echo "  <ol>"
    while IFS= read -r line; do
      if [[ "$line" == "---" ]]; then
        past_sep=1; continue
      fi
      if [[ "$target" == "before" && "$past_sep" -eq 0 && "$line" =~ ^[0-9]+\. ]]; then
        format_item "$line"
      elif [[ "$target" == "after" && "$past_sep" -eq 1 && "$line" =~ ^[0-9]+\. ]]; then
        format_item "$line"
      fi
    done <"$NOTES_FILE"
    echo "  </ol>"
  }
  case "$LANG_FILTER" in
    en) emit_block "after" "Changelog" ;;
    zh) emit_block "before" "更新日志" ;;
    *) emit_block "after" "Changelog"; emit_block "before" "更新日志" ;;
  esac
fi
