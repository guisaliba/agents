#!/usr/bin/env bash
set -Eeuo pipefail

# test.sh
#
# Verifies that the OpenCode agent stack is correctly set up.
# Checks both repo structure and local machine state.
# Use --repo-only to run deterministic fixtures without installed machine state.

repo_only=false
if [[ $# -gt 0 ]]; then
  if [[ $# -eq 1 && "$1" == "--repo-only" ]]; then
    repo_only=true
  else
    printf 'Usage: %s [--repo-only]\n' "$0" >&2
    exit 2
  fi
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
AGENT_STACK_HELPER="$DOTFILES_DIR/agents/lib/agent_stack.py"
SKILLS_MANIFEST="$DOTFILES_DIR/agents/skills.tsv"

failures=0
GITHUB_MCP_TOKEN_FILE="$HOME/.config/opencode/secrets/github-mcp-pat"
GITHUB_MCP_EXPECTED_JSON='{"type":"remote","url":"https://api.githubcopilot.com/mcp/","enabled":true,"oauth":false,"headers":{"Authorization":"Bearer {file:~/.config/opencode/secrets/github-mcp-pat}","X-MCP-Toolsets":"context,repos,issues,pull_requests,actions"}}'
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
AI_MEMORY_INSTRUCTIONS_FILE="$HOME/.config/opencode/ai-memory.md"
AI_MEMORY_INSTRUCTIONS_REFERENCE="~/.config/opencode/ai-memory.md"
AI_MEMORY_USER_SERVICE_FILE="$HOME/.config/systemd/user/ai-memory.service"
AI_MEMORY_MCP_EXPECTED_JSON='{"type":"remote","url":"http://127.0.0.1:49374/mcp","enabled":true}'
AI_MEMORY_MIN_VERSION="1.28.0"
AI_MEMORY_LLM_PROFILE_EXPECTED="opencode-go-deepseek"
AI_MEMORY_LLM_PROVIDER_EXPECTED="opencode"
AI_MEMORY_LLM_MODEL_EXPECTED="deepseek-v4-flash"
LEARN_PLUGIN_SPEC="github:guisaliba/opencode-learn#main"
LEARN_TEXT_MODEL_EXPECTED="opencode-go/deepseek-v4-flash"
LEARN_VISUAL_MODEL_EXPECTED="opencode-go/deepseek-v4-flash-vision-exp"
OPENCODE_SHELL_BLOCK_START="# >>> dotfiles OpenCode ai-memory wrapper >>>"
OPENCODE_SHELL_BLOCK_END="# <<< dotfiles OpenCode ai-memory wrapper <<<"

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

require_empty_file() {
  local path="$1"
  [[ -f "$path" && ! -s "$path" ]] && ok "empty file: $path" || not_ok "file is missing or not empty: $path"
}

require_file_mode() {
  local path="$1"
  local expected="$2"
  if python3 - "$path" "$expected" <<'PY'
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected = int(sys.argv[2], 8)
try:
    mode = stat.S_IMODE(path.stat().st_mode)
except OSError:
    raise SystemExit(1)
raise SystemExit(0 if mode == expected else 1)
PY
  then
    ok "file mode: $path == $expected"
  else
    not_ok "file mode mismatch: $path != $expected"
  fi
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

require_skill_manifest_entry() {
  local path="$SKILLS_MANIFEST"
  local provider="$1"
  local name="$2"
  local source="$3"
  local require_skill_file="$4"
  if python3 - "$path" "$provider" "$name" "$source" "$require_skill_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
expected = tuple(sys.argv[2:])
try:
    lines = path.read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)

for line in lines:
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    if tuple(line.split("\t")) == expected:
        raise SystemExit(0)

raise SystemExit(1)
PY
  then
    ok "skill manifest entry: $name"
  else
    not_ok "missing skill manifest entry: $name"
  fi
}

require_text_count() {
  local path="$1"
  local needle="$2"
  local expected="$3"
  if python3 - "$path" "$needle" "$expected" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
needle = sys.argv[2]
expected = int(sys.argv[3])
try:
    count = path.read_text(encoding="utf-8").count(needle)
except OSError:
    raise SystemExit(1)
raise SystemExit(0 if count == expected else 1)
PY
  then
    ok "text count: $path contains $needle exactly $expected time(s)"
  else
    not_ok "text count mismatch: $needle in $path"
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

require_env_assignment() {
  local path="$1"
  local name="$2"
  local expected="$3"
  if python3 - "$path" "$name" "$expected" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2]
expected = sys.argv[3]
pattern = re.compile(rf"^\s*{re.escape(name)}\s*=\s*(.*?)\s*$")
values = []

try:
    lines = path.read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)

for line in lines:
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    match = pattern.match(line)
    if match is None:
        continue
    value = match.group(1)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]
    values.append(value)

raise SystemExit(0 if values == [expected] else 1)
PY
  then
    ok "environment assignment: $name is managed"
  else
    not_ok "environment assignment mismatch: $name in $path"
  fi
}

env_assignment_value() {
  local path="$1"
  local name="$2"
  python3 - "$path" "$name" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2]
pattern = re.compile(rf"^\s*{re.escape(name)}\s*=\s*(.*?)\s*$")
value = None

try:
    lines = path.read_text(encoding="utf-8").splitlines()
except OSError:
    raise SystemExit(1)

for line in lines:
    if not line.strip() or line.lstrip().startswith("#"):
        continue
    match = pattern.match(line)
    if match is None:
        continue
    value = match.group(1)
    if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
        value = value[1:-1]

if value is None:
    raise SystemExit(1)
print(value.strip())
PY
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

require_json_literal() {
  local path="$1"
  local key="$2"
  local expected_json="$3"
  if python3 - "$path" "$key" "$expected_json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
key = sys.argv[2]

try:
    value = json.loads(path.read_text(encoding="utf-8"))
    for part in key.split("."):
        value = value[part]
    expected = json.loads(sys.argv[3])
except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError):
    raise SystemExit(1)

raise SystemExit(0 if value == expected else 1)
PY
  then
    ok "json literal: $key == $expected_json"
  else
    not_ok "json literal mismatch: $key != $expected_json in $path"
  fi
}

require_json_missing() {
  local path="$1"
  local key="$2"
  if [[ ! -f "$path" ]]; then
    not_ok "cannot inspect missing json file: $path"
    return
  fi
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

require_json_array_count() {
  local path="$1"
  local key="$2"
  local expected_value="$3"
  local expected_count="$4"
  if python3 - "$path" "$key" "$expected_value" "$expected_count" <<'PY'
import json
import sys
from pathlib import Path

try:
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    for part in sys.argv[2].split("."):
        value = value[part]
    if not isinstance(value, list):
        raise SystemExit(1)
    count = value.count(sys.argv[3])
    expected = int(sys.argv[4])
except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError, ValueError):
    raise SystemExit(1)

raise SystemExit(0 if count == expected else 1)
PY
  then
    ok "json array count: $key contains $expected_value exactly $expected_count time(s)"
  else
    not_ok "json array count mismatch: $key / $expected_value in $path"
  fi
}

require_json_array_item_count() {
  local path="$1"
  local key="$2"
  local expected_json="$3"
  local expected_count="$4"
  if python3 - "$path" "$key" "$expected_json" "$expected_count" <<'PY'
import json
import sys
from pathlib import Path

try:
    value = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
    for part in sys.argv[2].split("."):
        value = value[part]
    expected = json.loads(sys.argv[3])
    count = value.count(expected)
except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError, ValueError):
    raise SystemExit(1)

raise SystemExit(0 if count == int(sys.argv[4]) else 1)
PY
  then
    ok "json array item count: $key contains $expected_json exactly $expected_count time(s)"
  else
    not_ok "json array item count mismatch: $key / $expected_json in $path"
  fi
}

require_ai_memory_instructions_current() {
  local fixture_root expected
  fixture_root="$(mktemp -d)"
  expected="$fixture_root/ai-memory.md"

  if ai-memory install-instructions \
    --target "$expected" \
    --no-skills >/dev/null 2>&1 && cmp -s "$expected" "$AI_MEMORY_INSTRUCTIONS_FILE"; then
    ok "ai-memory routing instructions match the installed binary"
  else
    not_ok "ai-memory routing instructions are stale or missing"
  fi

  rm -rf -- "$fixture_root"
}

require_ai_memory_status() {
  local output cli_version provider_enabled expected_provider expected_model
  expected_provider="$(env_assignment_value "$AI_MEMORY_ENV_FILE" AI_MEMORY_LLM_PROVIDER)" || expected_provider=""
  expected_model="$(env_assignment_value "$AI_MEMORY_ENV_FILE" AI_MEMORY_LLM_MODEL)" || expected_model=""
  [[ -n "$expected_provider" ]] && provider_enabled=true || provider_enabled=false

  if output="$(ai-memory status --json 2>/dev/null)" && \
    cli_version="$(ai-memory --version 2>/dev/null)" && \
    python3 - \
      "$AI_MEMORY_MIN_VERSION" \
      "$cli_version" \
      "$provider_enabled" \
      "$expected_provider" \
      "$expected_model" \
      "$output" <<'PY'
import json
import re
import sys


def parse_version(value):
    match = re.search(r"\b(\d+)\.(\d+)\.(\d+)\b", value)
    if match is None:
        raise ValueError(f"unreadable version: {value!r}")
    return tuple(int(part) for part in match.groups())


minimum = parse_version(sys.argv[1])
cli = parse_version(sys.argv[2])
provider_enabled = sys.argv[3] == "true"
expected_provider = sys.argv[4]
expected_model = sys.argv[5]
payload = json.loads(sys.argv[6])
server = parse_version(str(payload["version"]))

if server < minimum or server != cli:
    raise SystemExit(1)

llm = payload["providers"]["llm"]
if provider_enabled:
    if (
        llm["status"] == "disabled"
        or llm["provider"] != expected_provider
        or llm["model"] != expected_model
    ):
        raise SystemExit(1)
elif llm["status"] != "disabled" or llm["provider"] is not None or llm["model"] is not None:
    raise SystemExit(1)
PY
  then
    ok "ai-memory server version and LLM policy are current"
  else
    not_ok "ai-memory status, server version, or loaded LLM policy is inconsistent"
  fi
}

require_ai_memory_llm_policy() {
  if (
    source "$DOTFILES_DIR/agents/apply.sh"
    profile="$(ai_memory_env_value DOTFILES_AI_MEMORY_LLM_PROFILE)"
    profile_spec="$(ai_memory_profile_spec "$profile")"
    IFS='|' read -r expected_provider expected_model credential <<<"$profile_spec"
    if ! ai_memory_profile_credential_ready "$credential"; then
      expected_provider=""
    fi
    actual_provider="$(ai_memory_env_value AI_MEMORY_LLM_PROVIDER)"
    actual_model="$(ai_memory_env_value AI_MEMORY_LLM_MODEL)"
    [[ "$actual_provider" == "$expected_provider" && "$actual_model" == "$expected_model" ]]
  ) >/dev/null 2>&1; then
    ok "ai-memory profile, credentials, provider, and model are consistent"
  else
    not_ok "ai-memory profile or credential activation is inconsistent"
  fi
}

test_opencode_json_merge() {
  local fixture_root fixture_home fixture_config fixture_token token_before first_config
  local malformed_home malformed_config malformed_before malformed_log
  local invalid_home invalid_config invalid_before invalid_log
  local instructions_home instructions_config instructions_before instructions_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_config="$fixture_home/.config/opencode/opencode.json"
  fixture_token="$fixture_home/.config/opencode/secrets/github-mcp-pat"
  token_before="$fixture_root/token-before"
  first_config="$fixture_root/first-opencode.json"

  mkdir -p "$(dirname "$fixture_config")"
  python3 - "$fixture_config" <<'PY'
import json
import sys
from pathlib import Path

config = {
    "$schema": "https://opencode.ai/config.json",
    "theme": "user-theme",
    "instructions": [
        "user-rules.md",
        "~/.config/opencode/ai-memory.md",
        "~/.config/opencode/ai-memory.md",
    ],
    "agent": {
        "general": {"temperature": 0.25},
        "custom": {"model": "user/custom-model"},
    },
    "plugin": [
        "user/plugin",
        ["github:guisaliba/opencode-learn#v0.0.1", {"textModel": "stale/model"}],
        "github:guisaliba/opencode-learn#main",
    ],
    "mcp": {
        "custom": {
            "type": "remote",
            "url": "https://example.invalid/mcp",
            "enabled": False,
            "headers": {"X-Custom": "keep"},
        },
        "github": {
            "type": "local",
            "command": ["obsolete-github-server"],
            "enabled": False,
        },
        "ai-memory": {
            "type": "remote",
            "url": "http://127.0.0.1:49374/mcp",
            "enabled": False,
            "headers": {"X-Obsolete": "remove"},
        },
    },
}
Path(sys.argv[1]).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    ensure_github_mcp_token_file
    merge_opencode_json
  ) >/dev/null 2>&1; then
    ok "OpenCode merge fixture applies without GitHub credentials"
  else
    not_ok "OpenCode merge fixture failed"
  fi

  require_empty_file "$fixture_token"
  require_file_mode "$fixture_token" "600"

  require_json_value "$fixture_config" "theme" "user-theme"
  require_json_array_count "$fixture_config" "instructions" "user-rules.md" "1"
  require_json_array_count "$fixture_config" "instructions" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" "1"
  require_json_array_count "$fixture_config" "plugin" "user/plugin" "1"
  require_json_array_count "$fixture_config" "plugin" "@plannotator/opencode@latest" "1"
  require_json_array_count "$fixture_config" "plugin" "$LEARN_PLUGIN_SPEC" "0"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    '["github:guisaliba/opencode-learn#v0.0.1",{"textModel":"stale/model"}]' \
    "0"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    "[\"$LEARN_PLUGIN_SPEC\",{\"textModel\":\"$LEARN_TEXT_MODEL_EXPECTED\",\"visualModel\":\"$LEARN_VISUAL_MODEL_EXPECTED\"}]" \
    "1"
  require_json_literal "$fixture_config" "agent.general.temperature" "0.25"
  require_json_value "$fixture_config" "agent.custom.model" "user/custom-model"
  require_json_value "$fixture_config" "mcp.custom.url" "https://example.invalid/mcp"
  require_json_value "$fixture_config" "mcp.custom.headers.X-Custom" "keep"
  require_json_value "$fixture_config" "mcp.github.type" "remote"
  require_json_value "$fixture_config" "mcp.github.url" "https://api.githubcopilot.com/mcp/"
  require_json_literal "$fixture_config" "mcp.github.enabled" "true"
  require_json_literal "$fixture_config" "mcp.github.oauth" "false"
  require_json_value "$fixture_config" "mcp.github.headers.Authorization" "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}"
  require_json_value "$fixture_config" "mcp.github.headers.X-MCP-Toolsets" "context,repos,issues,pull_requests,actions"
  require_json_literal "$fixture_config" "mcp.github" "$GITHUB_MCP_EXPECTED_JSON"
  require_json_literal "$fixture_config" "mcp.ai-memory" "$AI_MEMORY_MCP_EXPECTED_JSON"

  cp "$fixture_config" "$first_config"
  printf '%s\n' 'fixture-only-token' >"$fixture_token"
  chmod 0644 "$fixture_token"
  cp "$fixture_token" "$token_before"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    ensure_github_mcp_token_file
    merge_opencode_json
  ) >/dev/null 2>&1; then
    ok "OpenCode merge fixture applies a second time"
  else
    not_ok "second OpenCode merge fixture apply failed"
  fi
  if cmp -s "$first_config" "$fixture_config"; then
    ok "OpenCode merge is idempotent"
  else
    not_ok "OpenCode merge changed on the second apply"
  fi
  require_same_file "$token_before" "$fixture_token"
  require_file_mode "$fixture_token" "600"

  malformed_home="$fixture_root/malformed-home"
  malformed_config="$malformed_home/.config/opencode/opencode.json"
  malformed_before="$fixture_root/malformed-before.json"
  malformed_log="$fixture_root/malformed.log"
  mkdir -p "$(dirname "$malformed_config")"
  printf '%s\n' '{"theme":"keep","mcp":[]}' >"$malformed_config"
  cp "$malformed_config" "$malformed_before"
  if (
    HOME="$malformed_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_json
  ) >"$malformed_log" 2>&1; then
    not_ok "malformed OpenCode mcp structure was accepted"
  else
    ok "malformed OpenCode mcp structure fails"
  fi
  require_same_file "$malformed_before" "$malformed_config"
  require_contains "$malformed_log" "Expected 'mcp' to be an object"

  invalid_home="$fixture_root/invalid-home"
  invalid_config="$invalid_home/.config/opencode/opencode.json"
  invalid_before="$fixture_root/invalid-before.json"
  invalid_log="$fixture_root/invalid.log"
  mkdir -p "$(dirname "$invalid_config")"
  printf '%s\n' '{"theme":"keep", invalid}' >"$invalid_config"
  cp "$invalid_config" "$invalid_before"
  if (
    HOME="$invalid_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_json
  ) >"$invalid_log" 2>&1; then
    not_ok "invalid OpenCode JSON was accepted"
  else
    ok "invalid OpenCode JSON fails"
  fi
  require_same_file "$invalid_before" "$invalid_config"
  require_contains "$invalid_log" "Invalid JSON"

  instructions_home="$fixture_root/instructions-home"
  instructions_config="$instructions_home/.config/opencode/opencode.json"
  instructions_before="$fixture_root/instructions-before.json"
  instructions_log="$fixture_root/instructions.log"
  mkdir -p "$(dirname "$instructions_config")"
  printf '%s\n' '{"theme":"keep","instructions":"not-an-array"}' >"$instructions_config"
  cp "$instructions_config" "$instructions_before"
  if (
    HOME="$instructions_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_json
  ) >"$instructions_log" 2>&1; then
    not_ok "invalid OpenCode instructions structure was accepted"
  else
    ok "invalid OpenCode instructions structure fails"
  fi
  require_same_file "$instructions_before" "$instructions_config"
  require_contains "$instructions_log" "Expected 'instructions' to be an array"

  rm -rf -- "$fixture_root"
}

test_opencode_tui_json_merge() {
  local fixture_root fixture_home fixture_config first_config malformed_home malformed_config malformed_before malformed_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_config="$fixture_home/.config/opencode/tui.json"
  first_config="$fixture_root/first-tui.json"
  mkdir -p "$(dirname "$fixture_config")"
  python3 - "$fixture_config" <<'PY'
import json
import sys
from pathlib import Path

config = {
    "$schema": "https://opencode.ai/tui.json",
    "theme": "user-theme",
    "plugin": [
        "user/tui-plugin",
        ["github:guisaliba/opencode-learn#v0.0.1", {"ipcRoot": "/stale"}],
        "github:guisaliba/opencode-learn#main",
    ],
}
Path(sys.argv[1]).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_tui_json
  ) >/dev/null 2>&1; then
    ok "OpenCode TUI merge fixture applies"
  else
    not_ok "OpenCode TUI merge fixture failed"
  fi
  require_json_value "$fixture_config" "theme" "user-theme"
  require_json_array_count "$fixture_config" "plugin" "user/tui-plugin" "1"
  require_json_array_count "$fixture_config" "plugin" "$LEARN_PLUGIN_SPEC" "1"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    '["github:guisaliba/opencode-learn#v0.0.1",{"ipcRoot":"/stale"}]' \
    "0"

  cp "$fixture_config" "$first_config"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_tui_json
  ) >/dev/null 2>&1; then
    ok "OpenCode TUI merge fixture applies a second time"
  else
    not_ok "second OpenCode TUI merge fixture apply failed"
  fi
  require_same_file "$first_config" "$fixture_config"

  malformed_home="$fixture_root/malformed-home"
  malformed_config="$malformed_home/.config/opencode/tui.json"
  malformed_before="$fixture_root/malformed-before.json"
  malformed_log="$fixture_root/malformed.log"
  mkdir -p "$(dirname "$malformed_config")"
  printf '%s\n' '{"theme":"keep","plugin":{}}' >"$malformed_config"
  cp "$malformed_config" "$malformed_before"
  if (
    HOME="$malformed_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_tui_json
  ) >"$malformed_log" 2>&1; then
    not_ok "invalid OpenCode TUI plugin structure was accepted"
  else
    ok "invalid OpenCode TUI plugin structure fails"
  fi
  require_same_file "$malformed_before" "$malformed_config"
  require_contains "$malformed_log" "Expected 'plugin' to be an array or string"

  rm -rf -- "$fixture_root"
}

test_ai_memory_env_file() {
  local fixture_root fixture_home fixture_env fixture_config fixture_auth env_before first_env
  local oauth_home oauth_env oauth_auth oauth_before
  local malformed_home malformed_env malformed_auth malformed_auth_before malformed_env_before malformed_log
  local no_key_home no_key_env
  local opencode_home opencode_env
  local openai_api_home openai_api_env
  local disabled_home disabled_env
  local invalid_home invalid_env invalid_before invalid_log
  local auth_name auth_index env_auth_home config_auth_home
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_env="$fixture_home/.config/ai-memory/env"
  fixture_config="$fixture_home/.config/ai-memory/config.toml"
  env_before="$fixture_root/env-before"

  mkdir -p "$(dirname "$fixture_env")"
  printf '%s\n' 'AI_MEMORY_LLM_PROVIDER=fixture' >"$fixture_env"
  printf '%s\n' '[auth]' 'token_pepper = "fixture-pepper"' >"$fixture_config"
  chmod 0644 "$fixture_env"
  cp "$fixture_env" "$env_before"

  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    ensure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "ai-memory environment fixture applies"
  else
    not_ok "ai-memory environment fixture failed"
  fi

  require_same_file "$env_before" "$fixture_env"
  require_file_mode "$fixture_env" "600"

  printf '%s\n' \
    '# preserve this comment' \
    'UNRELATED_SETTING=keep' \
    'OPENCODE_API_KEY=fixture-secret' \
    'AI_MEMORY_LLM_PROVIDER=openai' \
    'AI_MEMORY_LLM_PROVIDER=stale-duplicate' \
    'AI_MEMORY_LLM_MODEL=stale-model' \
    'AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=false' \
    'AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED=true' >"$fixture_env"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "ai-memory provider policy fixture applies"
  else
    not_ok "ai-memory provider policy fixture failed"
  fi

  first_env="$fixture_root/first-env"
  cp "$fixture_env" "$first_env"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "ai-memory provider policy fixture applies a second time"
  else
    not_ok "second ai-memory provider policy fixture apply failed"
  fi
  require_same_file "$first_env" "$fixture_env"
  require_file_mode "$fixture_env" "600"
  require_contains "$fixture_env" "# preserve this comment"
  require_contains "$fixture_env" "UNRELATED_SETTING=keep"
  require_env_assignment "$fixture_env" "OPENCODE_API_KEY" "fixture-secret"
  require_env_assignment "$fixture_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "$AI_MEMORY_LLM_PROFILE_EXPECTED"
  require_env_assignment "$fixture_env" "AI_MEMORY_LLM_PROVIDER" "$AI_MEMORY_LLM_PROVIDER_EXPECTED"
  require_env_assignment "$fixture_env" "AI_MEMORY_LLM_MODEL" "$AI_MEMORY_LLM_MODEL_EXPECTED"
  require_env_assignment "$fixture_env" "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL" "true"
  require_env_assignment "$fixture_env" "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED" "false"

  no_key_home="$fixture_root/no-key-home"
  no_key_env="$no_key_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$no_key_env")" "$no_key_home/.local/share/opencode"
  printf '%s\n' 'UNRELATED_SETTING=keep' >"$no_key_env"
  printf '%s\n' '{"openai":{"type":"oauth","refresh":"opencode-only"}}' \
    >"$no_key_home/.local/share/opencode/auth.json"
  if (
    HOME="$no_key_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "default DeepSeek profile stays disabled without its API key"
  else
    not_ok "default DeepSeek zero-LLM fixture failed"
  fi
  require_env_assignment "$no_key_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "$AI_MEMORY_LLM_PROFILE_EXPECTED"
  require_env_assignment "$no_key_env" "AI_MEMORY_LLM_PROVIDER" ""
  require_env_assignment "$no_key_env" "AI_MEMORY_LLM_MODEL" "$AI_MEMORY_LLM_MODEL_EXPECTED"

  oauth_home="$fixture_root/oauth-home"
  oauth_env="$oauth_home/.config/ai-memory/env"
  oauth_auth="$oauth_home/.local/share/ai-memory/auth.json"
  oauth_before="$fixture_root/oauth-auth-before"
  mkdir -p "$(dirname "$oauth_env")" "$(dirname "$oauth_auth")"
  printf '%s\n' \
    'UNRELATED_SETTING=keep' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=openai-subscription-luna' >"$oauth_env"
  printf '%s\n' \
    '{"openai":{"type":"oauth","access":"access-token","refresh":"refresh-token","expires":4102444800000,"accountId":"account"},"oidc":{"type":"oauth"}}' \
    >"$oauth_auth"
  chmod 0600 "$oauth_auth"
  cp "$oauth_auth" "$oauth_before"
  if (
    HOME="$oauth_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "ai-memory OpenAI subscription profile enables with its OAuth token"
  else
    not_ok "ai-memory OpenAI subscription profile fixture failed"
  fi
  require_same_file "$oauth_before" "$oauth_auth"
  require_env_assignment "$oauth_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "openai-subscription-luna"
  require_env_assignment "$oauth_env" "AI_MEMORY_LLM_PROVIDER" "openai-oauth"
  require_env_assignment "$oauth_env" "AI_MEMORY_LLM_MODEL" "gpt-5.6-luna"

  malformed_home="$fixture_root/malformed-auth-home"
  malformed_env="$malformed_home/.config/ai-memory/env"
  malformed_auth="$malformed_home/.local/share/ai-memory/auth.json"
  malformed_auth_before="$fixture_root/malformed-auth-before"
  malformed_env_before="$fixture_root/malformed-env-before"
  malformed_log="$fixture_root/malformed-auth.log"
  mkdir -p "$(dirname "$malformed_env")" "$(dirname "$malformed_auth")"
  printf '%s\n' 'DOTFILES_AI_MEMORY_LLM_PROFILE=openai-subscription-luna' >"$malformed_env"
  printf '%s\n' '{malformed' >"$malformed_auth"
  cp "$malformed_auth" "$malformed_auth_before"
  cp "$malformed_env" "$malformed_env_before"
  if (
    HOME="$malformed_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >"$malformed_log" 2>&1; then
    not_ok "malformed ai-memory OAuth state was accepted"
  else
    ok "malformed ai-memory OAuth state fails safely"
  fi
  require_same_file "$malformed_auth_before" "$malformed_auth"
  require_same_file "$malformed_env_before" "$malformed_env"
  require_contains "$malformed_log" "Invalid ai-memory OpenAI OAuth state"

  opencode_home="$fixture_root/opencode-profile-home"
  opencode_env="$opencode_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$opencode_env")"
  printf '%s\n' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-deepseek' \
    'OPENCODE_API_KEY=fixture-secret' >"$opencode_env"
  if (
    HOME="$opencode_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "OpenCode Go DeepSeek profile enables with its separate key"
  else
    not_ok "OpenCode Go DeepSeek profile fixture failed"
  fi
  require_env_assignment "$opencode_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "opencode-go-deepseek"
  require_env_assignment "$opencode_env" "OPENCODE_API_KEY" "fixture-secret"
  require_env_assignment "$opencode_env" "AI_MEMORY_LLM_PROVIDER" "opencode"
  require_env_assignment "$opencode_env" "AI_MEMORY_LLM_MODEL" "deepseek-v4-flash"

  openai_api_home="$fixture_root/openai-api-profile-home"
  openai_api_env="$openai_api_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$openai_api_env")"
  printf '%s\n' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=openai-api-luna' \
    'OPENAI_API_KEY=fixture-secret' >"$openai_api_env"
  if (
    HOME="$openai_api_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "OpenAI API Luna profile enables with its Platform key"
  else
    not_ok "OpenAI API Luna profile fixture failed"
  fi
  require_env_assignment "$openai_api_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "openai-api-luna"
  require_env_assignment "$openai_api_env" "OPENAI_API_KEY" "fixture-secret"
  require_env_assignment "$openai_api_env" "AI_MEMORY_LLM_PROVIDER" "openai"
  require_env_assignment "$openai_api_env" "AI_MEMORY_LLM_MODEL" "gpt-5.6-luna"

  disabled_home="$fixture_root/disabled-profile-home"
  disabled_env="$disabled_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$disabled_env")" "$disabled_home/.local/share/ai-memory"
  printf '%s\n' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=disabled' \
    'OPENAI_API_KEY=fixture-secret' \
    'OPENCODE_API_KEY=fixture-secret' >"$disabled_env"
  cp "$oauth_auth" "$disabled_home/.local/share/ai-memory/auth.json"
  if (
    HOME="$disabled_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "disabled ai-memory profile stays in zero-LLM mode"
  else
    not_ok "disabled ai-memory profile fixture failed"
  fi
  require_env_assignment "$disabled_env" "AI_MEMORY_LLM_PROVIDER" ""
  require_env_assignment "$disabled_env" "AI_MEMORY_LLM_MODEL" ""

  invalid_home="$fixture_root/invalid-profile-home"
  invalid_env="$invalid_home/.config/ai-memory/env"
  invalid_before="$fixture_root/invalid-profile-before"
  invalid_log="$fixture_root/invalid-profile.log"
  mkdir -p "$(dirname "$invalid_env")"
  printf '%s\n' \
    'UNRELATED_SETTING=keep' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=not-a-profile' >"$invalid_env"
  cp "$invalid_env" "$invalid_before"
  if (
    HOME="$invalid_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    configure_ai_memory_env_file
  ) >"$invalid_log" 2>&1; then
    not_ok "invalid ai-memory profile was accepted"
  else
    ok "invalid ai-memory profile fails safely"
  fi
  require_same_file "$invalid_before" "$invalid_env"
  require_contains "$invalid_log" "Unsupported DOTFILES_AI_MEMORY_LLM_PROFILE"

  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    verify_ai_memory_no_static_auth_files
  ) >/dev/null 2>&1; then
    ok "ai-memory default auth files allow unauthenticated loopback"
  else
    not_ok "ai-memory default auth files were rejected"
  fi

  auth_index=0
  for auth_name in \
    AI_MEMORY_AUTH_TOKEN \
    AI_MEMORY_AUTH__BEARER_TOKEN \
    AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN
  do
    auth_index=$((auth_index + 1))
    env_auth_home="$fixture_root/env-auth-home-$auth_index"
    mkdir -p "$env_auth_home/.config/ai-memory"
    printf '%s=%s\n' "$auth_name" 'fixture-token' >"$env_auth_home/.config/ai-memory/env"
    if (
      HOME="$env_auth_home"
      source "$DOTFILES_DIR/agents/apply.sh"
      verify_ai_memory_no_static_auth_files
    ) >/dev/null 2>&1; then
      not_ok "ai-memory environment auth variable was accepted: $auth_name"
    else
      ok "ai-memory environment auth variable is rejected: $auth_name"
    fi
  done

  config_auth_home="$fixture_root/config-auth-home"
  mkdir -p "$config_auth_home/.config/ai-memory"
  printf '%s\n' '[auth]' 'bearer_token = "fixture-token"' >"$config_auth_home/.config/ai-memory/config.toml"
  if (
    HOME="$config_auth_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    verify_ai_memory_no_static_auth_files
  ) >/dev/null 2>&1; then
    not_ok "ai-memory config bearer token was accepted"
  else
    ok "ai-memory config bearer token is rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_agent_stack_helpers() {
  local fixture_root fixture_home fixture_env fixture_token fixture_config fixture_auth
  local real_target atomic_target atomic_expected malformed_manifest duplicate_manifest
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_env="$fixture_home/.config/ai-memory/env"
  fixture_token="$fixture_home/.config/opencode/secrets/github-mcp-pat"
  fixture_config="$fixture_home/.config/ai-memory/config.toml"
  fixture_auth="$fixture_home/.local/share/ai-memory/auth.json"
  real_target="$fixture_root/real-target"
  atomic_target="$fixture_root/atomic-target"
  atomic_expected="$fixture_root/atomic-expected"
  malformed_manifest="$fixture_root/malformed-skills.tsv"
  duplicate_manifest="$fixture_root/duplicate-skills.tsv"

  mkdir -p "$(dirname "$fixture_env")"
  printf '%s\n' \
    '# ignored comment' \
    'TEST_VALUE=first' \
    'TEST_VALUE = "second value"' \
    'EMPTY_VALUE=""' >"$fixture_env"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    [[ "$(ai_memory_env_value TEST_VALUE)" == "second value" ]]
    ! ai_memory_env_has_nonempty_value EMPTY_VALUE
  ); then
    ok "shared environment parser preserves last-value and empty-value behavior"
  else
    not_ok "shared environment parser changed last-value or empty-value behavior"
  fi

  printf '%s\n' 'AI_MEMORY_AUTH_TOKEN = "fixture-token"' >"$fixture_env"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    verify_ai_memory_no_static_auth_files
  ) >/dev/null 2>&1; then
    not_ok "quoted ai-memory auth assignment was accepted"
  else
    ok "quoted ai-memory auth assignment is rejected"
  fi

  mkdir -p "$(dirname "$fixture_token")"
  printf '%s\n' 'fixture' >"$real_target"
  ln -s "$real_target" "$fixture_token"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    ensure_github_mcp_token_file
  ) >/dev/null 2>&1; then
    not_ok "GitHub MCP token symlink was accepted"
  else
    ok "GitHub MCP token symlink is rejected"
  fi

  rm -f "$fixture_token"
  mkdir "$fixture_token"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    ensure_github_mcp_token_file
  ) >/dev/null 2>&1; then
    not_ok "GitHub MCP token directory was accepted"
  else
    ok "GitHub MCP token directory is rejected"
  fi

  rm -rf "$fixture_token"
  mkdir -p "$(dirname "$fixture_config")"
  ln -s "$real_target" "$fixture_config"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    initialize_ai_memory
  ) >/dev/null 2>&1; then
    not_ok "ai-memory config symlink was accepted"
  else
    ok "ai-memory config symlink is rejected before initialization"
  fi

  mkdir -p "$(dirname "$fixture_auth")"
  ln -s "$real_target" "$fixture_auth"
  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    ai_memory_openai_oauth_state
  ) >/dev/null 2>&1; then
    not_ok "ai-memory auth symlink was accepted"
  else
    ok "ai-memory auth symlink is rejected"
  fi

  printf '%s\n' 'new content' >"$atomic_expected"
  printf '%s\n' 'new content' | \
    python3 "$AGENT_STACK_HELPER" atomic-write "$atomic_target" 644 ".atomic." >/dev/null 2>&1
  require_same_file "$atomic_expected" "$atomic_target"
  require_file_mode "$atomic_target" "644"

  cp "$SKILLS_MANIFEST" "$malformed_manifest"
  printf '%s\n' 'broken-row' >>"$malformed_manifest"
  if python3 "$AGENT_STACK_HELPER" manifest "$malformed_manifest" >/dev/null 2>&1; then
    not_ok "malformed skill manifest row was accepted"
  else
    ok "malformed skill manifest row is rejected"
  fi

  cp "$SKILLS_MANIFEST" "$duplicate_manifest"
  printf '%s\n' $'upstream\tduplicate\tduplicate/source\tno' >>"$duplicate_manifest"
  printf '%s\n' $'local\tduplicate\tagents/skills/find-skills\tno' >>"$duplicate_manifest"
  if python3 "$AGENT_STACK_HELPER" manifest "$duplicate_manifest" >/dev/null 2>&1; then
    not_ok "duplicate skill manifest name was accepted"
  else
    ok "duplicate skill manifest name is rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_required_skill_installation() {
  local fixture_root fixture_home stub_bin install_log stdin_log expected_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  install_log="$fixture_root/install.log"
  stdin_log="$fixture_root/stdin.log"
  expected_log="$fixture_root/expected.log"
  mkdir -p "$stub_bin"
  mkdir -p \
    "$fixture_home/.agents/skills/learn-profile" \
    "$fixture_home/.agents/skills/learn-verify" \
    "$fixture_home/.agents/skills/learn-visual" \
    "$fixture_home/.agents/skills/probe" \
    "$fixture_home/.agents/skills/teach" \
    "$fixture_home/.agents/skills/user-owned"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$*" >>"$SKILL_INSTALL_LOG"' \
    'while IFS= read -r line; do printf '\''%s\n'\'' "$line" >>"$SKILL_STDIN_LOG"; done' >"$stub_bin/npx"
  chmod +x "$stub_bin/npx"
  : >"$stdin_log"

  if printf '%s\n' 'fixture-stdin-must-not-be-consumed' | (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    export SKILL_INSTALL_LOG="$install_log"
    export SKILL_STDIN_LOG="$stdin_log"
    source "$DOTFILES_DIR/agents/apply.sh"
    install_required_skills
  ) >/dev/null 2>&1; then
    ok "manifest-driven skill installation applies"
  else
    not_ok "manifest-driven skill installation failed"
  fi
  require_dir "$fixture_home/.agents/skills/find-skills"
  require_dir "$fixture_home/.agents/skills/auto-pr-review"
  require_dir "$fixture_home/.agents/skills/user-owned"
  for removed in learn-profile learn-verify learn-visual probe teach; do
    if [[ ! -e "$fixture_home/.agents/skills/$removed" ]]; then
      ok "legacy Alvar skill removed: $removed"
    else
      not_ok "legacy Alvar skill remains: $removed"
    fi
  done
  require_empty_file "$stdin_log"

  printf '%s\n' \
    '-y skills add https://github.com/almendili/skills -g -a opencode -s architecture-map -y --copy' \
    '-y skills add JuliusBrussee/caveman -g -a opencode -s caveman -y --copy' \
    '-y skills add mattpocock/skills@engineering/code-review -g -a opencode -s code-review -y --copy' \
    '-y skills add mattpocock/skills@productivity/grill-me -g -a opencode -s grill-me -y --copy' \
    '-y skills add mattpocock/skills@engineering/grill-with-docs -g -a opencode -s grill-with-docs -y --copy' \
    '-y skills add mattpocock/skills@productivity/handoff -g -a opencode -s handoff -y --copy' \
    '-y skills add mattpocock/skills@engineering/implement -g -a opencode -s implement -y --copy' \
    '-y skills add mattpocock/skills@engineering/setup-matt-pocock-skills -g -a opencode -s setup-matt-pocock-skills -y --copy' \
    '-y skills add mattpocock/skills@engineering/tdd -g -a opencode -s tdd -y --copy' \
    '-y skills add mattpocock/skills@productivity/teach -g -a opencode -s teach -y --copy' \
    '-y skills add mattpocock/skills@engineering/to-tickets -g -a opencode -s to-tickets -y --copy' \
    '-y skills add mattpocock/skills@engineering/triage -g -a opencode -s triage -y --copy' \
    '-y skills add mattpocock/skills@productivity/writing-for-agents -g -a opencode -s writing-for-agents -y --copy' \
    '-y skills add shadcn/improve -g -a opencode -s improve -y --copy' \
    '-y skills add boristane/agent-skills -g -a opencode -s logging-best-practices -y --copy' \
    '-y skills add https://github.com/cloudflare/skills -g -a opencode -y --copy' >"$expected_log"
  require_same_file "$expected_log" "$install_log"

  rm -rf -- "$fixture_root"
}

test_opencode_shell_override() {
  local fixture_root fixture_home aliases first_aliases stub_bin
  local ai_memory_log raw_log expected yolo_log
  local malformed_home malformed_aliases malformed_before malformed_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  aliases="$fixture_home/.bash_aliases"
  first_aliases="$fixture_root/first-bash-aliases"
  stub_bin="$fixture_root/bin"
  ai_memory_log="$fixture_root/ai-memory.log"
  raw_log="$fixture_root/raw-opencode.log"
  expected="$fixture_root/expected.log"
  yolo_log="$fixture_root/yolo.log"

  mkdir -p "$fixture_home" "$stub_bin"
  printf '%s\n' \
    'alias preserved-alias='\''printf preserved'\''' \
    '# >>> dotfiles OpenCode ai-memory wrapper >>>' \
    'alias opencode='\''stale-wrapper'\''' \
    '# <<< dotfiles OpenCode ai-memory wrapper <<<' >"$aliases"

  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_shell_override
  ) >/dev/null 2>&1; then
    ok "OpenCode Bash override fixture applies"
  else
    not_ok "OpenCode Bash override fixture failed"
  fi

  require_contains "$aliases" "alias preserved-alias='printf preserved'"
  require_text_count "$aliases" "$OPENCODE_SHELL_BLOCK_START" "1"
  require_text_count "$aliases" "$OPENCODE_SHELL_BLOCK_END" "1"
  require_contains "$aliases" 'opencode() {'
  require_contains "$aliases" 'opencode-raw() {'
  require_contains "$aliases" 'command ai-memory run opencode "$@"'
  cp "$aliases" "$first_aliases"

  if (
    HOME="$fixture_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_shell_override
  ) >/dev/null 2>&1; then
    ok "OpenCode Bash override fixture applies a second time"
  else
    not_ok "OpenCode Bash override second apply failed"
  fi
  require_same_file "$first_aliases" "$aliases"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_AI_MEMORY_LOG"' >"$stub_bin/ai-memory"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_RAW_LOG"' >"$stub_bin/opencode"
  chmod +x "$stub_bin/ai-memory" "$stub_bin/opencode"

  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    OPENCODE_TEST_RAW_LOG="$raw_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode -c "two words"'; then
    printf '%s\n' run opencode -c 'two words' >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode Bash function failed"
  fi

  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    OPENCODE_TEST_RAW_LOG="$raw_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode session list'; then
    printf '%s\n' run opencode session list >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode session utility forwarding failed"
  fi

  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    OPENCODE_TEST_RAW_LOG="$raw_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode-raw --version'; then
    printf '%s\n' --version >"$expected"
    require_same_file "$expected" "$raw_log"
  else
    not_ok "raw OpenCode escape hatch failed"
  fi

  : >"$ai_memory_log"
  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    OPENCODE_TEST_RAW_LOG="$raw_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode --yolo' >"$yolo_log" 2>&1; then
    not_ok "managed OpenCode Bash function accepted an unjailed --yolo start"
  else
    ok "managed OpenCode Bash function rejects an unjailed --yolo start"
  fi
  require_empty_file "$ai_memory_log"
  require_contains "$yolo_log" "Refusing an unjailed OpenCode dangerous-mode start"

  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    OPENCODE_TEST_RAW_LOG="$raw_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode --auto' >"$yolo_log" 2>&1; then
    not_ok "managed OpenCode Bash function accepted an unjailed --auto start"
  else
    ok "managed OpenCode Bash function rejects an unjailed --auto start"
  fi
  require_empty_file "$ai_memory_log"

  malformed_home="$fixture_root/malformed-home"
  malformed_aliases="$malformed_home/.bash_aliases"
  malformed_before="$fixture_root/malformed-before"
  malformed_log="$fixture_root/malformed.log"
  mkdir -p "$malformed_home"
  printf '%s\n' \
    'alias keep='\''printf keep'\''' \
    "$OPENCODE_SHELL_BLOCK_START" >"$malformed_aliases"
  cp "$malformed_aliases" "$malformed_before"
  if (
    HOME="$malformed_home"
    source "$DOTFILES_DIR/agents/apply.sh"
    merge_opencode_shell_override
  ) >"$malformed_log" 2>&1; then
    not_ok "malformed OpenCode Bash wrapper markers were accepted"
  else
    ok "malformed OpenCode Bash wrapper markers fail safely"
  fi
  require_same_file "$malformed_before" "$malformed_aliases"
  require_contains "$malformed_log" "Expected one balanced OpenCode wrapper block"

  rm -rf -- "$fixture_root"
}

test_optional_ai_jail() {
  local fixture_root stub_bin
  fixture_root="$(mktemp -d)"
  stub_bin="$fixture_root/bin"
  mkdir -p "$stub_bin"

  if (
    PATH="$stub_bin:/usr/bin:/bin"
    source "$DOTFILES_DIR/agents/apply.sh"
    report_optional_ai_jail
  ) >/dev/null 2>&1; then
    ok "apply accepts an unavailable optional ai-jail command"
  else
    not_ok "apply requires the optional ai-jail command"
  fi

  rm -rf -- "$fixture_root"
}

test_native_ai_memory_requirement() {
  local fixture_root stub_bin wrapper_log
  fixture_root="$(mktemp -d)"
  stub_bin="$fixture_root/bin"
  wrapper_log="$fixture_root/wrapper.log"
  mkdir -p "$stub_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''ai-memory 1.32.0\n'\''' >"$stub_bin/ai-memory"
  chmod +x "$stub_bin/ai-memory"

  if (
    PATH="$stub_bin:/usr/bin:/bin"
    source "$DOTFILES_DIR/agents/apply.sh"
    install_ai_memory
  ) >"$wrapper_log" 2>&1; then
    not_ok "Docker ai-memory wrapper was accepted as a native binary"
  else
    ok "Docker ai-memory wrapper is rejected before setup"
  fi
  require_contains "$wrapper_log" "ai-memory must be a native Linux executable"

  cp /bin/true "$stub_bin/ai-memory"
  if (
    PATH="$stub_bin:/usr/bin:/bin"
    source "$DOTFILES_DIR/agents/apply.sh"
    verify_native_ai_memory
  ) >/dev/null 2>&1; then
    ok "native Linux executable satisfies the ai-memory binary check"
  else
    not_ok "native Linux executable was rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_ai_memory_user_service_installation() {
  local fixture_root fixture_home stub_bin service_file first_service expected_service
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  service_file="$fixture_home/.config/systemd/user/ai-memory.service"
  first_service="$fixture_root/first-service"
  expected_service="$fixture_root/expected-service"
  mkdir -p "$stub_bin"
  printf '\177ELFfixture' >"$stub_bin/ai-memory"
  chmod +x "$stub_bin/ai-memory"

  printf '%s\n' \
    '# Managed by dotfiles/agents/apply.sh.' \
    '[Unit]' \
    'Description=ai-memory MCP server (user service)' \
    'Documentation=https://github.com/akitaonrails/ai-memory' \
    '' \
    '[Service]' \
    'Type=simple' \
    'EnvironmentFile=-%h/.config/ai-memory/env' \
    "ExecStart=\"$stub_bin/ai-memory\" --data-dir %h/.local/share/ai-memory --config %h/.config/ai-memory/config.toml serve --transport http --enable-web" \
    'Restart=on-failure' \
    'RestartSec=5s' \
    'NoNewPrivileges=true' \
    'PrivateTmp=true' \
    '' \
    '[Install]' \
    'WantedBy=default.target' >"$expected_service"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    source "$DOTFILES_DIR/agents/apply.sh"
    install_ai_memory_user_service
  ) >/dev/null 2>&1; then
    ok "missing ai-memory user service is installed"
  else
    not_ok "missing ai-memory user service was not installed"
  fi
  require_same_file "$expected_service" "$service_file"
  require_file_mode "$service_file" "644"

  cp "$service_file" "$first_service"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    source "$DOTFILES_DIR/agents/apply.sh"
    install_ai_memory_user_service
  ) >/dev/null 2>&1; then
    ok "ai-memory user service installation applies a second time"
  else
    not_ok "second ai-memory user service installation failed"
  fi
  require_same_file "$first_service" "$service_file"

  rm -rf -- "$fixture_root"
}

# Repo structure checks
printf '\n--- Repo Structure ---\n'

require_file "$DOTFILES_DIR/agents/AGENTS.md"
require_file "$DOTFILES_DIR/agents/apply.sh"
require_file "$DOTFILES_DIR/agents/test.sh"
require_file "$DOTFILES_DIR/agents/opencode/README.md"
require_file "$DOTFILES_DIR/agents/skills/README.md"
require_file "$AGENT_STACK_HELPER"
require_file "$SKILLS_MANIFEST"
require_file "$DOTFILES_DIR/bash/.bash_aliases"
require_executable "$DOTFILES_DIR/agents/apply.sh"
require_executable "$DOTFILES_DIR/agents/test.sh"
if manifest_rows="$(python3 "$AGENT_STACK_HELPER" manifest "$SKILLS_MANIFEST" 2>/dev/null)"; then
  manifest_valid=true
  ok "skill manifest is valid"
else
  manifest_valid=false
  not_ok "skill manifest is invalid"
fi
require_skill_manifest_entry "upstream" "architecture-map" "https://github.com/almendili/skills" "yes"
require_skill_manifest_entry "upstream" "code-review" "mattpocock/skills@engineering/code-review" "yes"
require_skill_manifest_entry "upstream" "implement" "mattpocock/skills@engineering/implement" "yes"
require_skill_manifest_entry "upstream" "teach" "mattpocock/skills@productivity/teach" "yes"
if [[ "$manifest_valid" == true ]]; then
  while IFS=$'\t' read -r provider name source_ref require_skill_file; do
    case "$provider" in
      local)
        require_dir "$DOTFILES_DIR/$source_ref"
        ;;
      upstream)
        if [[ ! -e "$DOTFILES_DIR/agents/skills/$name" ]]; then
          ok "$name is not locally vendored"
        else
          not_ok "$name must be installed from upstream, not locally vendored"
        fi
        ;;
    esac
  done <<<"$manifest_rows"
fi
require_contains "$DOTFILES_DIR/agents/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."
require_text_count "$DOTFILES_DIR/bash/.bash_aliases" "$OPENCODE_SHELL_BLOCK_START" "1"
require_text_count "$DOTFILES_DIR/bash/.bash_aliases" "$OPENCODE_SHELL_BLOCK_END" "1"

# OpenCode merge fixture checks
printf '\n--- OpenCode Merge Fixtures ---\n'

test_opencode_json_merge
test_opencode_tui_json_merge

# ai-memory secret-file fixture checks
printf '\n--- ai-memory File Fixtures ---\n'

test_ai_memory_env_file

# Shared helper fixture checks
printf '\n--- Shared Helper Fixtures ---\n'

test_agent_stack_helpers

# Manifest installation fixture checks
printf '\n--- Skill Installation Fixtures ---\n'

test_required_skill_installation

# Bash command override fixture checks
printf '\n--- OpenCode Bash Override Fixtures ---\n'

test_opencode_shell_override

# Optional ai-jail fixture checks
printf '\n--- Optional ai-jail Fixtures ---\n'

test_optional_ai_jail

# Native ai-memory fixture checks
printf '\n--- Native ai-memory Fixtures ---\n'

test_native_ai_memory_requirement
test_ai_memory_user_service_installation

if [[ "$repo_only" == "true" ]]; then
  printf '\n'
  if [[ "$failures" -gt 0 ]]; then
    printf 'agent stack repository tests failed: %s\n' "$failures" >&2
    exit 1
  fi
  printf 'agent stack repository tests passed\n'
  exit 0
fi

# Local machine checks
printf '\n--- Local Machine ---\n'

require_command python3
require_command bash
require_command opencode
require_command ai-memory
require_command rtk
require_command plannotator
require_file "$HOME/.config/opencode/plugins/rtk.ts"

opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
ai-memory --help >/dev/null 2>&1 && ok "ai-memory help runs" || not_ok "ai-memory help failed"
plannotator --help >/dev/null 2>&1 && ok "plannotator help runs" || not_ok "plannotator help failed"

if (
  source "$DOTFILES_DIR/agents/apply.sh"
  verify_native_ai_memory
  require_minimum_version ai-memory "$AI_MEMORY_MIN_VERSION"
) >/dev/null 2>&1; then
  ok "ai-memory is native and its version is supported"
else
  not_ok "ai-memory is not native, is older than $AI_MEMORY_MIN_VERSION, or is unreadable"
fi

if command -v ai-jail >/dev/null 2>&1; then
  ai-jail --help >/dev/null 2>&1 && ok "optional ai-jail help runs" || not_ok "optional ai-jail help failed"
else
  ok "optional ai-jail command is not installed"
fi

rewritten="$(rtk rewrite "git status --short" 2>/dev/null || true)"
[[ "$rewritten" == "rtk git status --short" ]] && ok "rtk rewrite runs" || not_ok "rtk rewrite failed"

require_file "$HOME/.config/opencode/AGENTS.md"
require_contains "$HOME/.config/opencode/AGENTS.md" "Required Capabilities"
require_contains "$HOME/.config/opencode/AGENTS.md" "ASD-STE100"
require_contains "$HOME/.config/opencode/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."
require_same_file "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
require_file "$HOME/.bash_aliases"
require_text_count "$HOME/.bash_aliases" "$OPENCODE_SHELL_BLOCK_START" "1"
require_text_count "$HOME/.bash_aliases" "$OPENCODE_SHELL_BLOCK_END" "1"
if bash -ic 'declare -F opencode >/dev/null && declare -F opencode-raw >/dev/null' \
  </dev/null >/dev/null 2>&1; then
  ok "interactive Bash loads managed opencode and opencode-raw functions"
else
  not_ok "interactive Bash does not load the managed OpenCode functions"
fi
require_file "$GITHUB_MCP_TOKEN_FILE"
require_file_mode "$GITHUB_MCP_TOKEN_FILE" "600"
require_json "$HOME/.config/opencode/opencode.json"
require_json_value "$HOME/.config/opencode/opencode.json" "model" "openai/gpt-5.6-sol"
require_json_value "$HOME/.config/opencode/opencode.json" "default_agent" "build"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.plan.model" "openai/gpt-5.6-sol"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.general.model" "opencode-go/deepseek-v4-flash"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.explore.model" "opencode-go/deepseek-v4-flash"
require_json_array_count "$HOME/.config/opencode/opencode.json" "instructions" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" "1"
require_json_array_count "$HOME/.config/opencode/opencode.json" "plugin" "$LEARN_PLUGIN_SPEC" "0"
require_json_array_item_count \
  "$HOME/.config/opencode/opencode.json" \
  "plugin" \
  "[\"$LEARN_PLUGIN_SPEC\",{\"textModel\":\"$LEARN_TEXT_MODEL_EXPECTED\",\"visualModel\":\"$LEARN_VISUAL_MODEL_EXPECTED\"}]" \
  "1"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.ai-memory" "$AI_MEMORY_MCP_EXPECTED_JSON"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.type" "remote"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.url" "https://api.githubcopilot.com/mcp/"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.github.enabled" "true"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.github.oauth" "false"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.headers.Authorization" "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.headers.X-MCP-Toolsets" "context,repos,issues,pull_requests,actions"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.github" "$GITHUB_MCP_EXPECTED_JSON"

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
require_file "$HOME/.config/opencode/tui.json"
require_json "$HOME/.config/opencode/tui.json"
require_json_array_count "$HOME/.config/opencode/tui.json" "plugin" "$LEARN_PLUGIN_SPEC" "1"

for retired in learn-profile learn-verify learn-visual probe; do
  if [[ ! -e "$HOME/.agents/skills/$retired" ]]; then
    ok "retired Alvar skill is absent: $retired"
  else
    not_ok "retired Alvar skill remains installed: $retired"
  fi
done

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

# ai-memory runtime
printf '\n--- ai-memory ---\n'

require_dir "$HOME/.local/share/ai-memory"
require_file "$AI_MEMORY_CONFIG_FILE"
require_file_mode "$AI_MEMORY_CONFIG_FILE" "600"
require_file "$AI_MEMORY_ENV_FILE"
require_file_mode "$AI_MEMORY_ENV_FILE" "600"
require_env_assignment "$AI_MEMORY_ENV_FILE" "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL" "true"
require_env_assignment "$AI_MEMORY_ENV_FILE" "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED" "false"
require_ai_memory_llm_policy
if [[ -f "$HOME/.local/share/ai-memory/auth.json" ]]; then
  require_file_mode "$HOME/.local/share/ai-memory/auth.json" "600"
fi
if (
  source "$DOTFILES_DIR/agents/apply.sh"
  verify_ai_memory_unauthenticated_loopback
) >/dev/null 2>&1; then
  ok "ai-memory loopback service has no bearer authentication"
else
  not_ok "ai-memory loopback authentication policy is inconsistent"
fi
require_file "$AI_MEMORY_INSTRUCTIONS_FILE"
require_contains "$AI_MEMORY_INSTRUCTIONS_FILE" "<!-- ai-memory:start -->"
require_contains "$AI_MEMORY_INSTRUCTIONS_FILE" "<!-- ai-memory:end -->"
require_ai_memory_instructions_current
require_file "$HOME/.config/opencode/plugins/ai-memory.ts"
require_contains "$HOME/.config/opencode/plugins/ai-memory.ts" 'Auto-generated by `ai-memory install-hooks --agent opencode --apply`'
require_contains "$HOME/.config/opencode/plugins/ai-memory.ts" 'const SERVER = "http://127.0.0.1:49374"'
require_contains "$HOME/.config/opencode/plugins/ai-memory.ts" 'const DEFAULT_PROJECT_STRATEGY = "repo-root";'
require_file "$AI_MEMORY_USER_SERVICE_FILE"
require_file_mode "$AI_MEMORY_USER_SERVICE_FILE" "644"
require_contains "$AI_MEMORY_USER_SERVICE_FILE" "# Managed by dotfiles/agents/apply.sh."
require_contains "$AI_MEMORY_USER_SERVICE_FILE" "--data-dir %h/.local/share/ai-memory"

systemctl --user is-enabled --quiet ai-memory.service >/dev/null 2>&1 && \
  ok "ai-memory user service is enabled" || not_ok "ai-memory user service is not enabled"
systemctl --user is-active --quiet ai-memory.service >/dev/null 2>&1 && \
  ok "ai-memory user service is active" || not_ok "ai-memory user service is not active"
require_ai_memory_status

# Required skills
printf '\n--- Skills ---\n'

if [[ "$manifest_valid" == true ]]; then
  while IFS=$'\t' read -r provider name source_ref require_skill_file; do
    require_dir "$HOME/.agents/skills/$name"
    if [[ "$require_skill_file" == yes ]]; then
      require_file "$HOME/.agents/skills/$name/SKILL.md"
    fi
  done <<<"$manifest_rows"
fi

# Result
printf '\n'
if [[ "$failures" -gt 0 ]]; then
  printf 'agent stack tests failed: %s\n' "$failures" >&2
  exit 1
fi

printf 'agent stack tests passed\n'
