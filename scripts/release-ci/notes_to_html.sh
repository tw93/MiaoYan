#!/usr/bin/env bash
# Convert .github/RELEASE_NOTES.md to appcast <description> inner HTML.
# Usage: notes_to_html.sh [path-to-RELEASE_NOTES.md]
# Output: HTML fragment suitable for CDATA in appcast.xml

set -euo pipefail

NOTES_FILE="${1:-.github/RELEASE_NOTES.md}"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Error: $NOTES_FILE not found" >&2
  exit 1
fi

MONSTER="$(head -1 "$NOTES_FILE" | sed 's/^# V[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]* //')"

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
    echo "  <h3>${MONSTER}</h3>"
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
  emit_section "Changelog"
  emit_section "更新日志"
else
  # Sectionless format: two blocks separated by "^---$"
  # Block before "---" and block after "---"; emit after-block first (English), then before-block (Chinese).
  emit_block() {
    local target="$1"  # "before" or "after"
    local in_target=0
    local past_sep=0
    echo "  <h3>${MONSTER}</h3>"
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
  emit_block "after"
  emit_block "before"
fi
