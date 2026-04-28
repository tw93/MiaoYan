#!/usr/bin/env bash
# Generate GitHub release HTML body from .github/RELEASE_NOTES.md.
# Usage: render_release_body.sh [path-to-RELEASE_NOTES.md]
# Output: GitHub release HTML to stdout

set -euo pipefail

NOTES_FILE="${1:-.github/RELEASE_NOTES.md}"

if [[ ! -f "$NOTES_FILE" ]]; then
  echo "Error: $NOTES_FILE not found" >&2
  exit 1
fi

HEADER="$(head -1 "$NOTES_FILE")"
VERSION="$(printf '%s' "$HEADER" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

format_item() {
  local line="$1"
  local body="${line#*. }"
  body="$(printf '%s' "$body" | sed 's/\*\*\([^*]*\)\*\*[：:][[:space:]]*/\<strong\>\1\<\/strong\>: /')"
  body="${body//\`/}"
  echo "    <li>${body}</li>"
}

cat <<EOF
<p align="center">
  <a href="https://miaoyan.app/" target="_blank">
    <img src="https://gw.alipayobjects.com/zos/k/t0/43.png" width="110" />
  </a>
  <h1 align="center">MiaoYan V${VERSION}</h1>
  <div align="center">A native Markdown editor for engineers.</div>
</p>
EOF

if grep -q "^## Changelog" "$NOTES_FILE" || grep -q "^## 更新日志" "$NOTES_FILE"; then
  emit_ol() {
    local section_header="$1"
    local in_section=0
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
  printf '\n<h3>Changelog</h3>\n'
  emit_ol "Changelog"
  printf '\n<h3>更新日志</h3>\n'
  emit_ol "更新日志"
else
  emit_block() {
    local target="$1"
    local past_sep=0
    echo "  <ol>"
    while IFS= read -r line; do
      if [[ "$line" == "---" ]]; then past_sep=1; continue; fi
      if [[ "$target" == "before" && "$past_sep" -eq 0 && "$line" =~ ^[0-9]+\. ]]; then format_item "$line"; fi
      if [[ "$target" == "after"  && "$past_sep" -eq 1 && "$line" =~ ^[0-9]+\. ]]; then format_item "$line"; fi
    done <"$NOTES_FILE"
    echo "  </ol>"
  }
  printf '\n<h3>Changelog</h3>\n'
  emit_block "after"
  printf '\n<h3>更新日志</h3>\n'
  emit_block "before"
fi

cat <<'FOOTER'

<hr />
<p>If you find MiaoYan useful, please consider giving it a star and recommending it to your friends.</p>

> https://github.com/tw93/MiaoYan
FOOTER
