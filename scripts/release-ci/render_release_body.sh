#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  render_release_body.sh --notes build/release-content.json --version 2.8.0 --output build/release-body.md
EOF
}

NOTES=""
VERSION=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --notes)
      NOTES="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --output)
      OUTPUT="$2"
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

[[ -z "$NOTES" || -z "$VERSION" || -z "$OUTPUT" ]] && {
  usage
  exit 1
}

mkdir -p "$(dirname "$OUTPUT")"

{
  echo "<p align=\"center\">"
  echo "  <a href=\"https://miaoyan.app/\" target=\"_blank\">"
  echo "    <img src=\"https://gw.alipayobjects.com/zos/k/t0/43.png\" width=\"110\" />"
  echo "  </a>"
  echo "  <h1 align=\"center\">MiaoYan V${VERSION}</h1>"
  echo "  <div align=\"center\">A native Markdown editor for engineers.</div>"
  echo "</p>"
  echo
  echo "### Changelog"
  i=1
  while IFS=$'\t' read -r title description; do
    echo "${i}. **${title}**: ${description}"
    i=$((i + 1))
  done < <(jq -r '.highlights_en[] | [.title, .description] | @tsv' "$NOTES")

  echo
  echo "### 更新日志"
  i=1
  while IFS=$'\t' read -r title description; do
    echo "${i}. **${title}**：${description}"
    i=$((i + 1))
  done < <(jq -r '.highlights_zh[] | [.title, .description] | @tsv' "$NOTES")

  echo
  echo "---"
  echo
  echo "If you find MiaoYan useful, please consider giving it a star and recommending it to your friends."
  echo
  echo "> https://github.com/tw93/Pake"
} >"$OUTPUT"
