#!/usr/bin/env bash
set -Eeuo pipefail

# test.sh
#
# Verifies that the OpenCode agent stack is correctly set up.
# Checks both repo structure and local machine state.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"

failures=0

ok() {
  printf 'ok: %s\n' "$*"
}

not_ok() {
  printf 'not ok: %s\n' "$*" >&2
  failures=$((failures + 1))
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] && ok "file exists: $path" || not_ok "missing file: $path"
}

require_executable() {
  local path="$1"
  [[ -x "$path" ]] && ok "executable: $path" || not_ok "not executable: $path"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 && ok "command exists: $cmd" || not_ok "missing command: $cmd"
}

require_dir() {
  local path="$1"
  [[ -d "$path" ]] && ok "dir exists: $path" || not_ok "missing dir: $path"
}

require_contains() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "$path" ]]; then
    not_ok "cannot search missing file: $path"
    return
  fi
  if python3 - "$path" "$needle" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
raise SystemExit(0 if needle in path.read_text(encoding="utf-8") else 1)
PY
  then
    ok "contains '$needle': $path"
  else
    not_ok "missing '$needle': $path"
  fi
}

require_json() {
  local path="$1"
  if python3 -m json.tool "$path" >/dev/null 2>&1; then
    ok "valid json: $path"
  else
    not_ok "invalid json: $path"
  fi
}

# Repo structure checks
log_repo() {
  printf '\n--- Repo Structure ---\n'
}

require_file "$DOTFILES_DIR/agents/AGENTS.md"
require_file "$DOTFILES_DIR/agents/apply.sh"
require_file "$DOTFILES_DIR/agents/test.sh"
require_file "$DOTFILES_DIR/agents/opencode/README.md"
require_file "$DOTFILES_DIR/agents/skills/README.md"
require_executable "$DOTFILES_DIR/agents/apply.sh"
require_executable "$DOTFILES_DIR/agents/test.sh"

# Local machine checks
printf '\n--- Local Machine ---\n'

require_command opencode
require_command rtk
require_command plannotator

opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
plannotator --help >/dev/null 2>&1 && ok "plannotator help runs" || not_ok "plannotator help failed"

rewritten="$(rtk rewrite "git status --short" 2>/dev/null || true)"
[[ "$rewritten" == "rtk git status --short" ]] && ok "rtk rewrite runs" || not_ok "rtk rewrite failed"

require_file "$HOME/.config/opencode/AGENTS.md"
require_contains "$HOME/.config/opencode/AGENTS.md" "Required Capabilities"
require_json "$HOME/.config/opencode/opencode.json"
require_contains "$HOME/.config/opencode/opencode.json" "@plannotator/opencode@latest"

# Required skills
printf '\n--- Skills ---\n'

for skill in \
  caveman \
  find-skills \
  grill-me \
  grill-with-docs \
  handoff \
  tdd \
  teach \
  writing-great-skills \
  improve \
  plannotator-review \
  plannotator-annotate \
  plannotator-last \
  plannotator-compound \
  plannotator-setup-goal \
  plannotator-visual-explainer
do
  require_dir "$HOME/.agents/skills/$skill"
done

# Result
printf '\n'
if [[ "$failures" -gt 0 ]]; then
  printf 'agent stack tests failed: %s\n' "$failures" >&2
  exit 1
fi

printf 'agent stack tests passed\n'