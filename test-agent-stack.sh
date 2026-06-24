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

require_hook_json_field() {
  local path="$1"
  local expr="$2"
  local label="$3"

  if python3 - "$path" "$expr" <<'PY'
import json
import sys
from pathlib import Path

data = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
expr = sys.argv[2]
raise SystemExit(0 if eval(expr, {}, {"data": data}) else 1)
PY
  then
    ok "$label"
  else
    not_ok "$label"
  fi
}

require_file "$DOTFILES_DIR/agents/AGENTS.md"
require_file "$DOTFILES_DIR/agents/hooks/ensure-agent-stack.sh"
require_file "$CHEZMOI_SRC/.chezmoitemplates/agents/AGENTS.md"
require_file "$CHEZMOI_SRC/dot_agents/bin/ensure-agent-stack.sh"
require_file "$CHEZMOI_SRC/dot_codex/AGENTS.md.tmpl"
require_file "$CHEZMOI_SRC/dot_config/opencode/AGENTS.md.tmpl"
require_file "$CHEZMOI_SRC/dot_pi/agent/AGENTS.md.tmpl"
require_file "$CHEZMOI_SRC/dot_claude/CLAUDE.md.tmpl"
require_file "$CHEZMOI_SRC/dot_claude/settings.json"

require_json "$CHEZMOI_SRC/dot_claude/settings.json"
require_json "$CHEZMOI_SRC/dot_codex/hooks.json"
require_json "$CHEZMOI_SRC/dot_config/opencode/opencode.json"

require_contains "$CHEZMOI_SRC/dot_claude/CLAUDE.md.tmpl" "{{ include \".chezmoitemplates/agents/AGENTS.md\" }}"
require_contains "$CHEZMOI_SRC/dot_claude/settings.json" "ensure-agent-stack.sh"
require_contains "$CHEZMOI_SRC/dot_claude/settings.json" "rtk hook claude"
require_contains "$CHEZMOI_SRC/dot_codex/hooks.json" "ensure-agent-stack.sh"

require_hook_json_field "$CHEZMOI_SRC/dot_claude/settings.json" "'SessionStart' in data.get('hooks', {})" "claude SessionStart hook configured"
require_hook_json_field "$CHEZMOI_SRC/dot_claude/settings.json" "'UserPromptSubmit' in data.get('hooks', {})" "claude UserPromptSubmit hook configured"
require_hook_json_field "$CHEZMOI_SRC/dot_claude/settings.json" "'PreToolUse' in data.get('hooks', {})" "claude PreToolUse hook configured"
require_hook_json_field "$CHEZMOI_SRC/dot_codex/hooks.json" "'SessionStart' in data.get('hooks', {})" "codex SessionStart hook configured"

for target in \
  "$HOME/.codex/AGENTS.md" \
  "$HOME/.config/opencode/AGENTS.md" \
  "$HOME/.pi/agent/AGENTS.md" \
  "$HOME/.claude/CLAUDE.md" \
  "$HOME/.agents/bin/ensure-agent-stack.sh" \
  "$HOME/.claude/settings.json" \
  "$HOME/.config/caveman/config.json"
do
  require_file "$target"
done

require_dir "$HOME/.agents/skills/caveman"
require_dir "$HOME/.claude/skills/caveman"
require_dir "$HOME/.pi/agent/extensions/caveman-autostart"

require_contains "$HOME/.codex/AGENTS.md" "Required global capabilities"
require_contains "$HOME/.config/opencode/AGENTS.md" "Required global capabilities"
require_contains "$HOME/.pi/agent/AGENTS.md" "Required global capabilities"
require_contains "$HOME/.claude/CLAUDE.md" "Required global capabilities"

require_command claude
require_command codex
require_command opencode
require_command pi
require_command rtk

claude --help >/dev/null 2>&1 && ok "claude help runs" || not_ok "claude help failed"
codex --help >/dev/null 2>&1 && ok "codex help runs" || not_ok "codex help failed"
opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
pi --help >/dev/null 2>&1 && ok "pi help runs" || not_ok "pi help failed"
rewritten="$(rtk rewrite "git status --short" 2>/dev/null || true)"
[[ "$rewritten" == "rtk git status --short" ]] && ok "rtk rewrite runs" || not_ok "rtk rewrite failed"

require_no_broken_symlinks "$HOME/.codex"
require_no_broken_symlinks "$HOME/.config/opencode"
require_no_broken_symlinks "$HOME/.pi/agent"
require_no_broken_symlinks "$HOME/.claude"
require_no_broken_symlinks "$HOME/.agents"

if [[ "$failures" -gt 0 ]]; then
  printf 'agent stack tests failed: %s\n' "$failures" >&2
  exit 1
fi

printf 'agent stack tests passed\n'
