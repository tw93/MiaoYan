#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  generate_release_content.sh \
    --tag V2.8.0 \
    --version 2.8.0 \
    --prev-tag V2.7.0 \
    --output build/release-content.json

Environment:
  AI_BASE_URL / ANTHROPIC_BASE_URL
  AI_API_KEY  / ANTHROPIC_API_KEY
  AI_MODEL    / ANTHROPIC_MODEL
  AI_REQUIRED (true|false, default: true)
EOF
}

TAG=""
VERSION=""
PREV_TAG=""
OUTPUT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)
      TAG="$2"
      shift 2
      ;;
    --version)
      VERSION="$2"
      shift 2
      ;;
    --prev-tag)
      PREV_TAG="$2"
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

[[ -z "$TAG" || -z "$VERSION" || -z "$OUTPUT" ]] && {
  usage
  exit 1
}

AI_BASE_URL="${AI_BASE_URL:-${ANTHROPIC_BASE_URL:-}}"
AI_API_KEY="${AI_API_KEY:-${ANTHROPIC_API_KEY:-}}"
AI_MODEL="${AI_MODEL:-${ANTHROPIC_MODEL:-gpt-5.3-codex}}"
AI_API_STYLE="${AI_API_STYLE:-auto}"
AI_REQUIRED="${AI_REQUIRED:-true}"
STYLE_EXAMPLE="${RELEASE_STYLE_EXAMPLE:-}"

mkdir -p "$(dirname "$OUTPUT")"

commit_range=""
if [[ -n "$PREV_TAG" ]] && git rev-parse "$PREV_TAG" >/dev/null 2>&1; then
  commit_range="${PREV_TAG}..${TAG}"
fi

if [[ -n "$commit_range" ]]; then
  commit_lines="$(git log --no-merges --pretty=format:'- %s (%h)' "$commit_range" | head -120 || true)"
  file_lines="$(git diff --name-only "$commit_range" | head -200 || true)"
else
  commit_lines="$(git log --no-merges --pretty=format:'- %s (%h)' "$TAG" -n 40 || true)"
  file_lines="$(git show --name-only --pretty='' "$TAG" | head -200 || true)"
fi

if [[ -z "$commit_lines" ]]; then
  commit_lines="- Internal improvements and maintenance"
fi

if [[ -z "$file_lines" ]]; then
  file_lines="(no changed files detected)"
fi

fallback_json() {
  local monsters emojis hash m_idx e_idx
  monsters=(
    "Zinogre"
    "Mizutsune"
    "Nargacuga"
    "Lagiacrus"
    "Glavenus"
    "Gore Magala"
    "Rathalos"
    "Brachydios"
    "Barioth"
    "Astalos"
  )
  emojis=("🍝" "🐾" "⚡️" "🌊" "🔥" "🦉" "🛡️" "🧭" "🎯" "🧩")

  hash="$(printf '%s' "$VERSION" | shasum -a 256 | awk '{print $1}')"
  m_idx=$((16#${hash:0:2} % ${#monsters[@]}))
  e_idx=$((16#${hash:2:2} % ${#emojis[@]}))

  local -a subjects
  while IFS= read -r line; do
    subjects+=("$line")
  done < <(git log --no-merges --pretty=format:'%s' "${commit_range:-$TAG}" | head -5)
  if [[ ${#subjects[@]} -eq 0 ]]; then
    subjects=("Maintenance updates and improvements")
  fi

  local tmp
  tmp="$(mktemp)"
  {
    printf '{\n'
    printf '  "monster_name": "%s",\n' "${monsters[$m_idx]}"
    printf '  "emoji": "%s",\n' "${emojis[$e_idx]}"
    printf '  "highlights_zh": [\n'
    local i
    for ((i = 0; i < ${#subjects[@]}; i++)); do
      local comma=""
      [[ $i -lt $((${#subjects[@]} - 1)) ]] && comma=","
      printf '    {"title":"更新 %d","description":"%s"}%s\n' "$((i + 1))" "$(printf '%s' "${subjects[$i]}" | sed 's/"/\\"/g')" "$comma"
    done
    printf '  ],\n'
    printf '  "highlights_en": [\n'
    for ((i = 0; i < ${#subjects[@]}; i++)); do
      local comma=""
      [[ $i -lt $((${#subjects[@]} - 1)) ]] && comma=","
      printf '    {"title":"Update %d","description":"%s"}%s\n' "$((i + 1))" "$(printf '%s' "${subjects[$i]}" | sed 's/"/\\"/g')" "$comma"
    done
    printf '  ]\n'
    printf '}\n'
  } >"$tmp"

  jq '.' "$tmp" >"$OUTPUT"
  rm -f "$tmp"
}

validate_and_write_json() {
  local in_json="$1"
  jq -e '
    type == "object" and
    (.monster_name | type == "string" and length > 0) and
    (.emoji | type == "string" and length > 0) and
    (.highlights_zh | type == "array" and length > 0) and
    (.highlights_en | type == "array" and length > 0) and
    ([.highlights_zh[] | (.title | type == "string" and length > 0) and (.description | type == "string" and length > 0)] | all) and
    ([.highlights_en[] | (.title | type == "string" and length > 0) and (.description | type == "string" and length > 0)] | all)
  ' <<<"$in_json" >/dev/null

  jq '
    .highlights_zh = (.highlights_zh[:5]) |
    .highlights_en = (.highlights_en[:5])
  ' <<<"$in_json" >"$OUTPUT"
}

if [[ -z "$AI_BASE_URL" || -z "$AI_API_KEY" ]]; then
  if [[ "$AI_REQUIRED" == "true" ]]; then
    echo "AI_REQUIRED=true but AI credentials are missing." >&2
    exit 1
  fi
  fallback_json
  exit 0
fi

api_style="$AI_API_STYLE"
if [[ "$api_style" == "auto" ]]; then
  if [[ "$AI_MODEL" == gpt-* || "$AI_MODEL" == o1* || "$AI_MODEL" == o3* || "$AI_MODEL" == o4* ]]; then
    api_style="responses"
  else
    api_style="anthropic"
  fi
fi

read -r -d '' prompt <<EOF || true
你在为 MiaoYan（macOS Markdown 应用）生成发布内容。

Version: ${VERSION}
Current tag: ${TAG}
Previous tag: ${PREV_TAG:-N/A}

Commits:
${commit_lines}

Changed files:
${file_lines}

请参考历史 appcast 风格：怪物名 + emoji，中英两段内容语义对应，每条是"短标题 + 一句描述"。
输出必须是 STRICT JSON（不要 markdown 代码块，不要解释文字）。
Schema:
{
  "monster_name": "Monster name for release title",
  "emoji": "single emoji",
  "highlights_zh": [
    {"title":"短标题","description":"一句具体描述"}
  ],
  "highlights_en": [
    {"title":"Short title","description":"One specific sentence"}
  ]
}

Rules:
1) Keep 3-5 items in each language.
2) zh/en items should correspond in meaning and order.
3) Prefer user-facing changes over internal refactors.
4) 标题要短，描述要具体，避免空话。
5) 不要编造提交中不存在的功能。
EOF

if [[ -n "$STYLE_EXAMPLE" ]]; then
  prompt="${prompt}

历史风格示例（仅供参考，不要逐字复用）:
${STYLE_EXAMPLE}"
fi

payload="$(
  if [[ "$api_style" == "responses" ]]; then
    jq -n \
      --arg model "$AI_MODEL" \
      --arg prompt "$prompt" \
      '{
        model: $model,
        input: $prompt,
        max_output_tokens: 1400
      }'
  else
    jq -n \
      --arg model "$AI_MODEL" \
      --arg prompt "$prompt" \
      '{
        model: $model,
        max_tokens: 1400,
        temperature: 0.2,
        messages: [
          {
            role: "user",
            content: $prompt
          }
        ]
      }'
  fi
)"

response_file="$(mktemp)"
if [[ "$api_style" == "responses" ]]; then
  endpoint="${AI_BASE_URL%/}"
  if [[ "$endpoint" != */responses ]]; then
    if [[ "$endpoint" == */v1 ]]; then
      endpoint="${endpoint}/responses"
    else
      endpoint="${endpoint}/v1/responses"
    fi
  fi

  curl_cmd=(
    curl -fsSL "$endpoint"
    -H "content-type: application/json"
    -H "authorization: Bearer ${AI_API_KEY}"
    -d "$payload"
  )
else
  endpoint="${AI_BASE_URL%/}"
  if [[ "$endpoint" != */messages ]]; then
    if [[ "$endpoint" == */v1 ]]; then
      endpoint="${endpoint}/messages"
    else
      endpoint="${endpoint}/v1/messages"
    fi
  fi

  curl_cmd=(
    curl -fsSL "$endpoint"
    -H "content-type: application/json"
    -H "x-api-key: ${AI_API_KEY}"
    -H "anthropic-version: 2023-06-01"
    -d "$payload"
  )
fi

if ! "${curl_cmd[@]}" >"$response_file"; then
  if [[ "$AI_REQUIRED" == "true" ]]; then
    echo "AI request failed and AI_REQUIRED=true." >&2
    exit 1
  fi
  fallback_json
  rm -f "$response_file"
  exit 0
fi

text="$(
  jq -r '
    .output_text
    // ([.output[]? | .content[]? | select(.type == "output_text" or .type == "text") | (.text // .content // "")] | join("\n"))
    // ([.content[]? | select(.type == "text") | .text] | join("\n"))
    // .completion
    // .choices[0].message.content
    // ""
  ' "$response_file"
)"
rm -f "$response_file"

candidate="$(printf '%s' "$text" | sed -e 's/^```json[[:space:]]*//' -e 's/^```[[:space:]]*//' -e 's/[[:space:]]*```$//')"
if ! jq -e '.' >/dev/null 2>&1 <<<"$candidate"; then
  candidate="$(printf '%s' "$text" | perl -0777 -ne 'if(/\{.*\}/s){print $&}')"
fi

if [[ -z "$candidate" ]] || ! jq -e '.' >/dev/null 2>&1 <<<"$candidate"; then
  if [[ "$AI_REQUIRED" == "true" ]]; then
    echo "AI returned invalid JSON and AI_REQUIRED=true." >&2
    exit 1
  fi
  fallback_json
  exit 0
fi

if ! validate_and_write_json "$candidate"; then
  if [[ "$AI_REQUIRED" == "true" ]]; then
    echo "AI JSON schema validation failed and AI_REQUIRED=true." >&2
    exit 1
  fi
  fallback_json
  exit 0
fi
