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

# Extract monster name + emoji from "# V3.2.0 Zinogre ⚡"
MONSTER="$(head -1 "$NOTES_FILE" | sed 's/^# V[0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]* //')"

emit_section() {
  local section_header="$1"  # e.g. "Changelog" or "更新日志"
  local in_section=0

  echo "  <h3>${MONSTER}</h3>"
  echo "  <ol>"
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+"$section_header" ]]; then
      in_section=1
      continue
    fi
    if [[ "$in_section" -eq 1 && "$line" =~ ^##[[:space:]] ]]; then
      break
    fi
    if [[ "$in_section" -eq 1 && "$line" =~ ^[0-9]+\. ]]; then
      # Strip leading "N. " then convert **Title**: or **标题**：
      body="${line#*. }"
      # Convert **text**: rest  →  <strong>text</strong>: rest
      body="$(printf '%s' "$body" | sed 's/\*\*\([^*]*\)\*\*[：:][[:space:]]*/\<strong\>\1\<\/strong\>：/')"
      # Strip any remaining markdown backticks
      body="${body//\`/}"
      echo "    <li>${body}</li>"
    fi
  done <"$NOTES_FILE"
  echo "  </ol>"
}

emit_section "Changelog"
emit_section "更新日志"
