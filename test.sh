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

require_same_file() {
  local expected="$1"
  local actual="$2"
  if cmp -s "$expected" "$actual"; then
    ok "files match: $expected == $actual"
  else
    not_ok "files differ: $expected != $actual"
  fi
}

require_json_value() {
  local path="$1"
  local key="$2"
  local expected="$3"
  if python3 - "$path" "$key" "$expected" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]
expected = sys.argv[3]

try:
    value = json.loads(path.read_text(encoding="utf-8"))
    for part in key.split("."):
        value = value[part]
except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError):
    raise SystemExit(1)

raise SystemExit(0 if value == expected else 1)
PY
  then
    ok "json value: $key == $expected"
  else
    not_ok "json value mismatch: $key != $expected in $path"
  fi
}

require_json_missing() {
  local path="$1"
  local key="$2"
  if python3 - "$path" "$key" <<'PY'
import json
import sys
from pathlib import Path

value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
for part in sys.argv[2].split("."):
    if not isinstance(value, dict) or part not in value:
        raise SystemExit(0)
    value = value[part]
raise SystemExit(1)
PY
  then
    ok "json key absent: $key"
  else
    not_ok "unexpected json key: $key in $path"
  fi
}

# Repo structure checks
printf '\n--- Repo Structure ---\n'

require_file "$DOTFILES_DIR/agents/AGENTS.md"
require_file "$DOTFILES_DIR/agents/apply.sh"
require_file "$DOTFILES_DIR/agents/test.sh"
require_file "$DOTFILES_DIR/agents/opencode/README.md"
require_file "$DOTFILES_DIR/agents/skills/README.md"
require_executable "$DOTFILES_DIR/agents/apply.sh"
require_executable "$DOTFILES_DIR/agents/test.sh"
require_contains "$DOTFILES_DIR/agents/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."

# Local machine checks
printf '\n--- Local Machine ---\n'

require_command python3
require_command opencode
require_command rtk
require_command plannotator
require_file "$HOME/.config/opencode/plugins/rtk.ts"

opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
plannotator --help >/dev/null 2>&1 && ok "plannotator help runs" || not_ok "plannotator help failed"

rewritten="$(rtk rewrite "git status --short" 2>/dev/null || true)"
[[ "$rewritten" == "rtk git status --short" ]] && ok "rtk rewrite runs" || not_ok "rtk rewrite failed"

require_file "$HOME/.config/opencode/AGENTS.md"
require_contains "$HOME/.config/opencode/AGENTS.md" "Required Capabilities"
require_contains "$HOME/.config/opencode/AGENTS.md" "ASD-STE100"
require_contains "$HOME/.config/opencode/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."
require_same_file "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
require_json "$HOME/.config/opencode/opencode.json"
require_json_value "$HOME/.config/opencode/opencode.json" "model" "openai/gpt-5.6-sol"
require_json_value "$HOME/.config/opencode/opencode.json" "default_agent" "build"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.plan.model" "openai/gpt-5.6-sol"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.general.model" "opencode-go/deepseek-v4-flash"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.explore.model" "opencode-go/deepseek-v4-flash"

available_agents="$(opencode agent list 2>/dev/null || true)"
if [[ "$available_agents" == *$'\nscout (subagent)\n'* ]]; then
  require_json_value "$HOME/.config/opencode/opencode.json" "agent.scout.model" "opencode-go/deepseek-v4-flash"
elif [[ "$available_agents" == *$'\nscout ('* ]]; then
  not_ok "scout exists but is not a built-in subagent"
else
  require_json_missing "$HOME/.config/opencode/opencode.json" "agent.scout"
  ok "native scout subagent is unavailable; no custom fallback configured"
fi

require_contains "$HOME/.config/opencode/opencode.json" "@plannotator/opencode@latest"

for mcp in \
  cloudflare-api \
  cloudflare-docs \
  cloudflare-bindings \
  cloudflare-builds \
  cloudflare-observability \
  linear
do
  require_contains "$HOME/.config/opencode/opencode.json" "$mcp"
done

require_contains "$HOME/.config/opencode/opencode.json" "https://mcp.linear.app/mcp"

# Required skills
printf '\n--- Skills ---\n'

for skill in \
  caveman \
  find-skills \
  auto-pr-review \
  grill-me \
  grill-with-docs \
  handoff \
  setup-matt-pocock-skills \
  tdd \
  teach \
  to-tickets \
  triage \
  writing-for-agents \
  improve \
  logging-best-practices \
  plannotator-review \
  plannotator-annotate \
  plannotator-last \
  plannotator-compound \
  plannotator-setup-goal \
  plannotator-visual-explainer \
  agents-sdk \
  cloudflare \
  cloudflare-email-service \
  cloudflare-one \
  cloudflare-one-migrations \
  durable-objects \
  sandbox-migrate-to-next \
  sandbox-next \
  sandbox-stable \
  turnstile-spin \
  web-perf \
  workers-best-practices \
  wrangler
do
  require_dir "$HOME/.agents/skills/$skill"
done

for skill in find-skills auto-pr-review; do
  require_file "$HOME/.agents/skills/$skill/SKILL.md"
done

# Result
printf '\n'
if [[ "$failures" -gt 0 ]]; then
  printf 'agent stack tests failed: %s\n' "$failures" >&2
  exit 1
fi

printf 'agent stack tests passed\n'
