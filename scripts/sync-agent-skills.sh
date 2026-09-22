#!/usr/bin/env bash
# Keep the ignored Claude compatibility mirror aligned with the tracked
# .agents/skills source without touching unrelated private Claude skills.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
canonical_root="${repo_root}/.agents/skills"
mirror_root="${repo_root}/.claude/skills"
mode="${1:-}"
[[ -n "${mode}" ]] || mode="--check"

reject_symlink_components() {
  local candidate="$1"
  case "${candidate}" in
    "${repo_root}" | "${repo_root}"/*) ;;
    *)
      echo "ERROR: skill sync path escaped repository root: ${candidate}" >&2
      exit 1
      ;;
  esac

  while [[ "${candidate}" != "${repo_root}" ]]; do
    if [[ -L "${candidate}" ]]; then
      echo "ERROR: refusing skill sync through symlink: ${candidate}" >&2
      exit 1
    fi
    candidate="$(dirname "${candidate}")"
  done
}

case "${mode}" in
  --check | --write) ;;
  *)
    echo "Usage: bash scripts/sync-agent-skills.sh [--check|--write]" >&2
    exit 2
    ;;
esac

if [[ ! -d "${canonical_root}" ]]; then
  echo "ERROR: canonical skill directory is missing: ${canonical_root}" >&2
  exit 1
fi
reject_symlink_components "${canonical_root}"

canonical_symlink="$(find "${canonical_root}" -type l -print -quit)"
if [[ -n "${canonical_symlink}" ]]; then
  echo "ERROR: canonical project skill tree contains a symlink: ${canonical_symlink}" >&2
  exit 1
fi

canonical_files=(
  "appstore/SKILL.md"
  "code-review/SKILL.md"
  "github-ops/SKILL.md"
  "lint/SKILL.md"
  "release/SKILL.md"
)
drift=0

# The explicit project-owned set catches deletions. Extra directories under the
# ignored Claude tree remain allowed because they may be private user Skills.
while IFS= read -r source; do
  [[ -n "${source}" ]] || continue
  relative="${source#"${canonical_root}/"}"
  declared=0
  for expected in "${canonical_files[@]}"; do
    if [[ "${relative}" == "${expected}" ]]; then
      declared=1
      break
    fi
  done
  if [[ "${declared}" -eq 0 ]]; then
    echo "ERROR: undeclared canonical project skill file: .agents/skills/${relative}" >&2
    exit 1
  fi
done < <(find "${canonical_root}" -type f -print | LC_ALL=C sort)

for relative in "${canonical_files[@]}"; do
  source="${canonical_root}/${relative}"
  mirror="${mirror_root}/${relative}"
  reject_symlink_components "${source}"
  mirror_directory="$(dirname "${mirror}")"
  if [[ -L "${mirror_directory}" ]]; then
    # A compatibility link is valid only for this exact canonical skill.
    # Validate its parent before following it, and never write through the link.
    reject_symlink_components "$(dirname "${mirror_directory}")"
    resolved_directory="$(cd "${mirror_directory}" 2>/dev/null && pwd -P)" || resolved_directory=""
    if [[ "${resolved_directory}" != "$(dirname "${source}")" ]]; then
      echo "ERROR: Claude skill link does not target its canonical directory: ${mirror_directory}" >&2
      exit 1
    fi
    if [[ ! -f "${source}" ]]; then
      echo "ERROR: missing canonical project skill file: .agents/skills/${relative}" >&2
      exit 1
    fi
    continue
  fi
  reject_symlink_components "${mirror}"

  if [[ ! -f "${source}" ]]; then
    echo "DRIFT: missing canonical project skill file: .agents/skills/${relative}" >&2
    drift=1
    continue
  fi

  if [[ "${mode}" == "--write" ]]; then
    mkdir -p "$(dirname "${mirror}")"
    if [[ -e "${mirror}" && ! -f "${mirror}" ]]; then
      echo "ERROR: Claude mirror target is not a regular file: ${mirror}" >&2
      exit 1
    fi
    temporary_mirror="$(mktemp "${mirror}.tmp.XXXXXX")"
    if ! cp -p "${source}" "${temporary_mirror}"; then
      rm -f "${temporary_mirror}"
      exit 1
    fi
    if ! mv -f "${temporary_mirror}" "${mirror}"; then
      rm -f "${temporary_mirror}"
      exit 1
    fi
  elif [[ ! -f "${mirror}" ]]; then
    echo "DRIFT: missing Claude mirror for .agents/skills/${relative}" >&2
    drift=1
  elif ! cmp -s "${source}" "${mirror}"; then
    echo "DRIFT: .claude/skills/${relative} differs from .agents/skills/${relative}" >&2
    drift=1
  fi

done

if [[ "${mode}" == "--write" ]]; then
  if [[ "${drift}" -ne 0 ]]; then
    exit 1
  fi
  echo "OK: synced ${#canonical_files[@]} canonical project skill files to the local Claude mirror"
elif [[ "${drift}" -ne 0 ]]; then
  echo "Run: bash scripts/sync-agent-skills.sh --write" >&2
  exit 1
else
  echo "OK: ${#canonical_files[@]} local Claude skill mirrors match .agents/skills"
fi
