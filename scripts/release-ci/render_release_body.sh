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

# "# V3.2.0 Zinogre ⚡" -> version "3.2.0"
HEADER="$(head -1 "$NOTES_FILE")"
VERSION="$(printf '%s' "$HEADER" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')"

emit_ol() {
  local section_header="$1"
  local in_section=0
  echo "  <ol>"
  while IFS= read -r line; do
    if [[ "$line" =~ ^##[[:space:]]+"$section_header" ]]; then
      in_section=1; continue
    fi
    if [[ "$in_section" -eq 1 && "$line" =~ ^##[[:space:]] ]]; then break; fi
    if [[ "$in_section" -eq 1 && "$line" =~ ^[0-9]+\. ]]; then
      body="${line#*. }"
      # **Title**: desc  ->  <strong>Title</strong>: desc
      body="$(printf '%s' "$body" | sed 's/\*\*\([^*]*\)\*\*[：:][[:space:]]*/\<strong\>\1\<\/strong\>: /')"
      body="${body//\`/}"
      echo "    <li>${body}</li>"
    fi
  done <"$NOTES_FILE"
  echo "  </ol>"
}

cat <<EOF
<p align="center">
  <a href="https://miaoyan.app/" target="_blank">
    <img src="https://gw.alipayobjects.com/zos/k/t0/43.png" width="110" />
  </a>
  <h1 align="center">MiaoYan V${VERSION}</h1>
  <div align="center">A native Markdown editor for engineers.</div>
</p>

<h3>Changelog</h3>
EOF

emit_ol "Changelog"

printf '\n<h3>更新日志</h3>\n'

emit_ol "更新日志"

cat <<'FOOTER'

<hr />
<p>If you find MiaoYan useful, please consider giving it a star and recommending it to your friends.</p>

> https://github.com/tw93/MiaoYan
FOOTER
