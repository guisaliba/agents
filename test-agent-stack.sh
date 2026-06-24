#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CHEZMOI_SRC="${CHEZMOI_SRC:-$DOTFILES_DIR/chezmoi}"

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

require_dir() {
  local path="$1"
  [[ -d "$path" ]] && ok "dir exists: $path" || not_ok "missing dir: $path"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 && ok "command exists: $cmd" || not_ok "missing command: $cmd"
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
  if python3 -m json.tool "$path" >/dev/null; then
    ok "valid json: $path"
  else
    not_ok "invalid json: $path"
  fi
}

require_no_broken_symlinks() {
  local path="$1"
  if [[ ! -e "$path" ]]; then
    ok "skip missing symlink scan: $path"
    return
  fi

  local broken
  broken="$(find "$path" -xtype l -print 2>/dev/null || true)"
  if [[ -z "$broken" ]]; then
    ok "no broken symlinks: $path"
  else
    not_ok "broken symlinks under $path: $broken"
  fi
}

require_file "$DOTFILES_DIR/agents/AGENTS.md"
require_file "$CHEZMOI_SRC/.chezmoitemplates/agents/AGENTS.md"
require_file "$CHEZMOI_SRC/dot_config/opencode/AGENTS.md.tmpl"
require_file "$CHEZMOI_SRC/dot_pi/agent/AGENTS.md.tmpl"

require_json "$CHEZMOI_SRC/dot_config/opencode/opencode.json"

for target in \
  "$HOME/.config/opencode/AGENTS.md" \
  "$HOME/.pi/agent/AGENTS.md" \
  "$HOME/.config/caveman/config.json"
do
  require_file "$target"
done

require_dir "$HOME/.agents/skills/caveman"
require_dir "$HOME/.pi/agent/extensions/caveman-autostart"

require_contains "$HOME/.config/opencode/AGENTS.md" "Required global capabilities"
require_contains "$HOME/.pi/agent/AGENTS.md" "Required global capabilities"

require_command opencode
require_command pi
require_command rtk

opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
pi --help >/dev/null 2>&1 && ok "pi help runs" || not_ok "pi help failed"
rewritten="$(rtk rewrite "git status --short" 2>/dev/null || true)"
[[ "$rewritten" == "rtk git status --short" ]] && ok "rtk rewrite runs" || not_ok "rtk rewrite failed"

require_no_broken_symlinks "$HOME/.config/opencode"
require_no_broken_symlinks "$HOME/.pi/agent"
require_no_broken_symlinks "$HOME/.agents"

if [[ "$failures" -gt 0 ]]; then
  printf 'agent stack tests failed: %s\n' "$failures" >&2
  exit 1
fi

printf 'agent stack tests passed\n'
