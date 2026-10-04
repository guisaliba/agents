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
REPO_DIR="$SCRIPT_DIR"
AGENT_STACK_HELPER="$REPO_DIR/lib/agent_stack.py"
SKILLS_MANIFEST="$REPO_DIR/skills.tsv"
if [[ "$(uname -s)" == Darwin ]] && command -v brew >/dev/null 2>&1; then
  PATH="$(brew --prefix)/bin:$PATH"
fi
PATH="$HOME/.opencode/bin:$HOME/.local/bin:$HOME/bin:$PATH"
export PATH

failures=0
GITHUB_MCP_TOKEN_FILE="$HOME/.config/opencode/secrets/github-mcp-pat"
GITHUB_MCP_EXPECTED_JSON='{"type":"remote","url":"https://api.githubcopilot.com/mcp/","disabled":false,"oauth":false,"headers":{"Authorization":"Bearer {file:~/.config/opencode/secrets/github-mcp-pat}","X-MCP-Toolsets":"context,repos,issues,pull_requests,actions"}}'
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
AI_MEMORY_INSTRUCTIONS_FILE="$HOME/.config/opencode/ai-memory.md"
AI_MEMORY_INSTRUCTIONS_REFERENCE="~/.config/opencode/ai-memory.md"
AI_MEMORY_USER_SERVICE_FILE="$HOME/.config/systemd/user/ai-memory.service"
AI_MEMORY_LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/com.github.akitaonrails.ai-memory.plist"
AI_MEMORY_LAUNCH_AGENT_LABEL="com.github.akitaonrails.ai-memory"
AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="$HOME/.config/ai-memory/com.github.akitaonrails.ai-memory.plist"
AI_MEMORY_LAUNCH_DAEMON_FILE="/Library/LaunchDaemons/com.github.akitaonrails.ai-memory.plist"
AI_MEMORY_MCP_EXPECTED_JSON='{"type":"remote","url":"http://127.0.0.1:49374/mcp","disabled":false}'
# The published ai-memory endpoint is a property of this host's declared role,
# not of its operating system and not of a hostname baked into this file. A
# server host leaves AI_MEMORY_SERVER_URL unset and answers on loopback; a
# client host sets it to the published origin. Deriving the expectation means a
# fork can point at its own server and the assertions still mean something.
# Read in a subshell so the environment file cannot alter the rest of the run.
AI_MEMORY_EXPECTED_SERVER_URL="$(
  if [[ -f "$AI_MEMORY_ENV_FILE" ]]; then
    set -a
    # shellcheck disable=SC1090
    . "$AI_MEMORY_ENV_FILE"
    set +a
  fi
  printf '%s' "${AI_MEMORY_SERVER_URL:-}"
)"
AI_MEMORY_EXPECTED_SERVER_URL="${AI_MEMORY_EXPECTED_SERVER_URL:-http://127.0.0.1:49374}"
AI_MEMORY_MIN_VERSION="1.28.0"
AI_MEMORY_RELEASE_VERSION_EXPECTED="2.1.1"
AI_MEMORY_MACOS_AARCH64_SHA256_EXPECTED="1cc2acdbbd62cc7ecf6e1fe91515ea77786910b2c102f1fe8781aa6c0357eb64"
AI_MEMORY_LLM_PROFILE_EXPECTED="opencode-go-deepseek-v4.1-flash"
AI_MEMORY_LLM_PROVIDER_EXPECTED="opencode"
AI_MEMORY_LLM_MODEL_EXPECTED="deepseek-v4.1-flash"
BUN_MIN_VERSION="1.3.0"
LEARN_REPOSITORY_URL_EXPECTED="https://github.com/guisaliba/learn.git"
LEARN_BRANCH="main"
LEARN_INSTALL_DIR="$HOME/.local/share/opencode/learn"
LEARN_PLUGIN_SPEC="$LEARN_INSTALL_DIR"
LEARN_LEGACY_PLUGIN_BASE="github:guisaliba/learn"
LEARN_OLDER_PLUGIN_BASE="github:guisaliba/opencode-learn"
OPENCODE_MIN_VERSION="2.0.18"
OPENCODE_TUI_THEME_EXPECTED="orng"
OPENCODE_TUI_SIDEBAR_KEYBIND_ID="session.sidebar.toggle"
OPENCODE_TUI_SIDEBAR_KEYBIND_EXPECTED="ctrl+b"
OPENCODE_TUI_BACKGROUND_KEYBIND_ID="session.background"
OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_ID="input.move.left"
OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_EXPECTED="left"
OPENCODE_SERVER_LAUNCH_AGENT_LABEL="com.opencode.server"
OPENCODE_SERVER_ENV_FILE="$HOME/.config/opencode/server.env"
OPENCODE_SERVER_LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/$OPENCODE_SERVER_LAUNCH_AGENT_LABEL.plist"
OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE="$HOME/.config/opencode/$OPENCODE_SERVER_LAUNCH_AGENT_LABEL.plist"
OPENCODE_SERVER_LAUNCH_DAEMON_FILE="/Library/LaunchDaemons/$OPENCODE_SERVER_LAUNCH_AGENT_LABEL.plist"
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

require_file_content() {
  local path="$1"
  local expected="$2"
  local actual=""
  if [[ -f "$path" ]]; then
    actual="$(tr -d '\r\n' <"$path")"
  fi
  if [[ "$actual" == "$expected" ]]; then
    ok "file content: $path == $expected"
  else
    not_ok "file content mismatch: $path has [$actual] instead of [$expected]"
  fi
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

require_json_keybind() {
  local path="$1"
  local keybind_id="$2"
  local expected_json="$3"
  if python3 - "$path" "$keybind_id" "$expected_json" <<'PY'
import json
import sys
from pathlib import Path

try:
    keybinds = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))["keybinds"]
    value = keybinds[sys.argv[2]]
    expected = json.loads(sys.argv[3])
except (FileNotFoundError, json.JSONDecodeError, KeyError, TypeError):
    raise SystemExit(1)

raise SystemExit(0 if value == expected else 1)
PY
  then
    ok "json keybind: $keybind_id == $expected_json"
  else
    not_ok "json keybind mismatch: $keybind_id != $expected_json in $path"
  fi
}

profile_names() {
  (
    source "$REPO_DIR/apply.sh"
    ai_memory_profile_list
  )
}

subagent_profile_names() {
  (
    source "$REPO_DIR/apply.sh"
    opencode_subagent_profile_list
  )
}

profile_field() {
  local name="$1"
  local field="$2"
  (
    source "$REPO_DIR/apply.sh"
    spec="$(ai_memory_profile_spec "$name")" || exit 1
    IFS='|' read -r provider model credential subagent_model <<<"$spec"
    case "$field" in
      provider) printf '%s\n' "$provider" ;;
      model) printf '%s\n' "$model" ;;
      credential) printf '%s\n' "$credential" ;;
      subagent) printf '%s\n' "$subagent_model" ;;
      *) exit 2 ;;
    esac
  )
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
  set -a
  source "$AI_MEMORY_ENV_FILE"
  set +a
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
    source "$REPO_DIR/apply.sh"
    profile="$(ai_memory_selected_profile)"
    profile_spec="$(ai_memory_profile_spec "$profile")"
    IFS='|' read -r expected_provider expected_model credential expected_subagent_model <<<"$profile_spec"
    if ! ai_memory_llm_enabled || ! ai_memory_profile_credential_ready "$credential"; then
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
  local fixture_root fixture_home fixture_config fixture_token fixture_learn_plugin token_before first_config
  local selected_profile profile_home profile_config profile_env
  local malformed_home malformed_config malformed_before malformed_log
  local invalid_home invalid_config invalid_before invalid_log
  local instructions_home instructions_config instructions_before instructions_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_config="$fixture_home/.config/opencode/opencode.json"
  fixture_token="$fixture_home/.config/opencode/secrets/github-mcp-pat"
  fixture_learn_plugin="$fixture_home/.local/share/opencode/learn"
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
        "rtk",
        "rtk@0.50.0",
        ["github:guisaliba/opencode-learn#v0.0.1", {"textModel": "stale/model"}],
        ["github:guisaliba/learn#v0.0.1", {"textModel": "stale/model"}],
        "github:guisaliba/learn#main",
    ],
    "plugins": [
        "-rtk",
        {"package": "@rtk-ai/rtk@0.50.0"},
        {"package": "~/.config/opencode/plugins/rtk.ts", "options": {"legacy": True}},
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
        "open-design": {
            "type": "local",
            "command": ["obsolete-open-design"],
            "enabled": True,
        },
    },
    "skills": {"paths": ["/user/skills", "/home/user/open-design/skills"]},
}
Path(sys.argv[1]).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

  if (
    HOME="$fixture_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    source "$REPO_DIR/apply.sh"
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
  require_json_value "$fixture_config" "model" "openai/gpt-6-luna"
  require_json_value "$fixture_config" "agents.plan.model" "openai/gpt-6-luna"
  require_json_array_count "$fixture_config" "instructions" "user-rules.md" "1"
  require_json_array_count "$fixture_config" "instructions" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" "1"
  require_json_array_count "$fixture_config" "plugins" "user/plugin" "1"
  require_json_array_count "$fixture_config" "plugins" "-rtk" "1"
  require_json_literal \
    "$fixture_config" \
    "plugins" \
    '["user/plugin","-rtk",{"package":"@plannotator/opencode@latest","options":{"workflow":"plan-agent","planningAgents":["plan"]}}]'
  require_json_array_item_count \
    "$fixture_config" \
    "plugins" \
    '{"package":"@plannotator/opencode@latest","options":{"workflow":"plan-agent","planningAgents":["plan"]}}' \
    "1"
  require_json_array_count "$fixture_config" "plugins" "$fixture_learn_plugin" "0"
  require_json_array_item_count \
    "$fixture_config" \
    "plugins" \
    '["github:guisaliba/opencode-learn#v0.0.1",{"textModel":"stale/model"}]' \
    "0"
  require_json_array_item_count \
    "$fixture_config" \
    "plugins" \
    '["github:guisaliba/learn#v0.0.1",{"textModel":"stale/model"}]' \
    "0"
  require_json_value "$fixture_config" "agents.general.model" "opencode-go/deepseek-v4.1-flash"
  require_json_value "$fixture_config" "agents.explore.model" "opencode-go/deepseek-v4.1-flash"
  require_json_literal "$fixture_config" "agents.general.request.body.temperature" "0.25"
  require_json_value "$fixture_config" "agents.custom.model" "user/custom-model"
  require_json_value "$fixture_config" "mcp.servers.custom.url" "https://example.invalid/mcp"
  require_json_value "$fixture_config" "mcp.servers.custom.headers.X-Custom" "keep"
  require_json_literal "$fixture_config" "mcp.servers.custom.disabled" "true"
  require_json_value "$fixture_config" "mcp.servers.github.type" "remote"
  require_json_value "$fixture_config" "mcp.servers.github.url" "https://api.githubcopilot.com/mcp/"
  require_json_literal "$fixture_config" "mcp.servers.github.disabled" "false"
  require_json_literal "$fixture_config" "mcp.servers.github.oauth" "false"
  require_json_value "$fixture_config" "mcp.servers.github.headers.Authorization" "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}"
  require_json_value "$fixture_config" "mcp.servers.github.headers.X-MCP-Toolsets" "context,repos,issues,pull_requests,actions"
  require_json_literal "$fixture_config" "mcp.servers.github" "$GITHUB_MCP_EXPECTED_JSON"
  require_json_literal "$fixture_config" "mcp.servers.ai-memory" "$AI_MEMORY_MCP_EXPECTED_JSON"
  require_json_missing "$fixture_config" "mcp.servers.open-design"
  require_json_array_count "$fixture_config" "skills" "/user/skills" "1"
  require_json_array_count "$fixture_config" "skills" "/home/user/open-design/skills" "0"
  require_json_literal "$fixture_config" "compaction.auto" "false"
  for stale_key in agent mode plugin permission command provider snapshot attachment small_model; do
    require_json_missing "$fixture_config" "$stale_key"
  done

  cp "$fixture_config" "$first_config"
  printf '%s\n' 'fixture-only-token' >"$fixture_token"
  chmod 0644 "$fixture_token"
  cp "$fixture_token" "$token_before"
  if (
    HOME="$fixture_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    source "$REPO_DIR/apply.sh"
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

  for selected_profile in $(profile_names); do
    profile_home="$fixture_root/profile-home-$selected_profile"
    profile_config="$profile_home/.config/opencode/opencode.json"
    profile_env="$profile_home/.config/ai-memory/env"
    mkdir -p "$(dirname "$profile_config")" "$(dirname "$profile_env")"
    printf '%s\n' "DOTFILES_AI_MEMORY_LLM_PROFILE=$selected_profile" >"$profile_env"
    if (
      HOME="$profile_home"
      LEARN_INSTALL_DIR="$fixture_learn_plugin"
      source "$REPO_DIR/apply.sh"
      merge_opencode_json
    ) >/dev/null 2>&1; then
      ok "OpenCode merge applies for profile: $selected_profile"
    else
      not_ok "OpenCode merge failed for profile: $selected_profile"
    fi
    require_json_value "$profile_config" "agents.general.model" "$(profile_field "$selected_profile" subagent)"
    require_json_value "$profile_config" "agents.explore.model" "$(profile_field "$selected_profile" subagent)"
  done

  # One profile drives the ai-memory LLM, the subagents, and the title agent.
  # The three used to be separate, and that let a stale title model survive
  # because small_model was migrated with setdefault and never corrected.
  profile_home="$fixture_root/profile-home-unified"
  profile_config="$profile_home/.config/opencode/opencode.json"
  profile_env="$profile_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$profile_config")" "$(dirname "$profile_env")"
  printf '%s\n' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-deepseek-v4.1-flash' \
    'OPENCODE_API_KEY=fixture-secret' \
    'AGENTS_AI_MEMORY_LLM_ENABLED=false' >"$profile_env"
  printf '%s\n' \
    '{"model":"keep","small_model":"opencode-go/deepseek-v4-flash"}' >"$profile_config"
  if (
    HOME="$profile_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    source "$REPO_DIR/apply.sh"
    merge_opencode_json
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "one profile drives the LLM, the subagents and the title agent"
  else
    not_ok "unified profile fixture failed"
  fi
  require_json_value "$profile_config" "agents.general.model" "opencode-go/deepseek-v4.1-flash"
  require_json_value "$profile_config" "agents.explore.model" "opencode-go/deepseek-v4.1-flash"
  # The stale small_model id must not survive into agents.title.
  require_json_value "$profile_config" "agents.title.model" "opencode-go/deepseek-v4.1-flash"
  require_env_assignment "$profile_env" "AI_MEMORY_LLM_PROVIDER" ""
  require_env_assignment "$profile_env" "AI_MEMORY_LLM_MODEL" "deepseek-v4.1-flash"

  # A second profile must move all three together, not just some of them.
  profile_home="$fixture_root/profile-home-unified-muse"
  profile_config="$profile_home/.config/opencode/opencode.json"
  profile_env="$profile_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$profile_config")" "$(dirname "$profile_env")"
  printf '%s\n' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-muse-spark-1.3-contributor' >"$profile_env"
  if (
    HOME="$profile_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    source "$REPO_DIR/apply.sh"
    merge_opencode_json
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    require_json_value "$profile_config" "agents.general.model" "opencode-go/muse-spark-1.3-contributor"
    require_json_value "$profile_config" "agents.title.model" "opencode-go/muse-spark-1.3-contributor"
    require_env_assignment "$profile_env" "AI_MEMORY_LLM_MODEL" "muse-spark-1.3-contributor"
  else
    not_ok "muse unified profile fixture failed"
  fi

  # A client must not be able to select a profile. Its sessions execute on the
  # server, so the server owns the value and the client is told where it comes
  # from instead of carrying a stale copy.
  client_profile_home="$fixture_root/client-profile-home"
  client_profile_config="$client_profile_home/.config/opencode/opencode.json"
  client_profile_env="$client_profile_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$client_profile_config")" "$(dirname "$client_profile_env")"
  printf '%s\n' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-muse-spark-1.3-contributor' >"$client_profile_env"
  printf '%s\n' '{"model":"keep","agents":{"title":{"model":"opencode-go/stale"}}}' >"$client_profile_config"
  if (
    HOME="$client_profile_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    AI_MEMORY_SERVER_URL="https://server.example.test:8443"
    AI_MEMORY_LOOPBACK_SERVER_URL="http://127.0.0.1:49374"
    AI_MEMORY_AUTH_TOKEN_FILE="$client_profile_home/.config/ai-memory/client-token"
    export AI_MEMORY_SERVER_URL AI_MEMORY_LOOPBACK_SERVER_URL AI_MEMORY_AUTH_TOKEN_FILE
    source "$REPO_DIR/apply.sh"
    merge_opencode_json
  ) >"$fixture_root/client-profile.log" 2>&1; then
    ok "a client host does not select a profile"
    require_json_value "$client_profile_config" "model" "openai/gpt-6-luna"
    if python3 -c "
import json, sys
data = json.load(open(sys.argv[1]))
agents = data.get('agents') or {}
bad = [n for n, c in agents.items() if isinstance(c, dict) and c.get('model') == 'opencode-go/stale']
raise SystemExit(1 if bad else 0)
" "$client_profile_config"; then
      ok "a client does not carry a stale agent model"
    else
      not_ok "a client kept a stale agent model"
    fi
    require_contains "$fixture_root/client-profile.log" "server"
  else
    not_ok "client profile fixture failed"
  fi

  profile_home="$fixture_root/profile-home-invalid"
  profile_config="$profile_home/.config/opencode/opencode.json"
  profile_env="$profile_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$profile_config")" "$(dirname "$profile_env")"
  printf '%s\n' 'DOTFILES_AI_MEMORY_LLM_PROFILE=unknown-model' >"$profile_env"
  printf '%s\n' '{"model":"keep"}' >"$profile_config"
  cp "$profile_config" "$fixture_root/invalid-profile-json-before"
  if (
    HOME="$profile_home"
    source "$REPO_DIR/apply.sh"
    merge_opencode_json
  ) >"$fixture_root/invalid-profile-json.log" 2>&1; then
    not_ok "an unsupported profile was accepted"
  else
    ok "an unsupported profile fails safely"
  fi
  require_same_file "$fixture_root/invalid-profile-json-before" "$profile_config"
  require_contains "$fixture_root/invalid-profile-json.log" "Unsupported DOTFILES_AI_MEMORY_LLM_PROFILE"

  malformed_home="$fixture_root/malformed-home"
  malformed_config="$malformed_home/.config/opencode/opencode.json"
  malformed_before="$fixture_root/malformed-before.json"
  malformed_log="$fixture_root/malformed.log"
  mkdir -p "$(dirname "$malformed_config")"
  printf '%s\n' '{"theme":"keep","mcp":[]}' >"$malformed_config"
  cp "$malformed_config" "$malformed_before"
  if (
    HOME="$malformed_home"
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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

test_opencode_cli_json_merge() {
  local fixture_root fixture_home cli_config tui_config first_config malformed_home malformed_config malformed_before malformed_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  cli_config="$fixture_home/.config/opencode/cli.json"
  tui_config="$fixture_home/.config/opencode/tui.json"
  first_config="$fixture_root/first-cli.json"
  mkdir -p "$(dirname "$tui_config")"
  python3 - "$tui_config" <<'PY'
import json
import sys
from pathlib import Path

config = {
    "$schema": "https://opencode.ai/tui.json",
    "theme": "user-theme",
    "keybinds": {
        "command.palette.show": "ctrl+k",
        "session.sidebar.toggle": "ctrl+shift+b",
    },
}
Path(sys.argv[1]).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

  if (
    HOME="$fixture_home"
    source "$REPO_DIR/apply.sh"
    merge_opencode_cli_json
  ) >/dev/null 2>&1; then
    ok "OpenCode V2 CLI merge fixture applies"
  else
    not_ok "OpenCode V2 CLI merge fixture failed"
  fi
  require_file "$cli_config"
  require_json_value "$cli_config" '$schema' "https://opencode.ai/v2/cli.json"
  require_json_value "$cli_config" "theme.name" "$OPENCODE_TUI_THEME_EXPECTED"
  require_json_keybind "$cli_config" "$OPENCODE_TUI_SIDEBAR_KEYBIND_ID" '"ctrl+b"'
  require_json_keybind "$cli_config" "$OPENCODE_TUI_BACKGROUND_KEYBIND_ID" "false"
  require_json_keybind "$cli_config" "$OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_ID" '"left"'
  require_json_keybind "$cli_config" "command.palette.show" '"ctrl+k"'
  [[ ! -e "$tui_config" ]] && ok "managed tui.json is retired" || not_ok "managed tui.json remains"

  cp "$cli_config" "$first_config"
  if (
    HOME="$fixture_home"
    source "$REPO_DIR/apply.sh"
    merge_opencode_cli_json
  ) >/dev/null 2>&1; then
    ok "OpenCode V2 CLI merge fixture applies a second time"
  else
    not_ok "second OpenCode V2 CLI merge fixture failed"
  fi
  require_same_file "$first_config" "$cli_config"

  malformed_home="$fixture_root/malformed-home"
  malformed_config="$malformed_home/.config/opencode/cli.json"
  malformed_before="$fixture_root/malformed-before.json"
  malformed_log="$fixture_root/malformed.log"
  mkdir -p "$(dirname "$malformed_config")"
  printf '%s\n' '{"theme":"keep","keybinds":[]}' >"$malformed_config"
  cp "$malformed_config" "$malformed_before"
  if (
    HOME="$malformed_home"
    source "$REPO_DIR/apply.sh"
    merge_opencode_cli_json
  ) >"$malformed_log" 2>&1; then
    not_ok "invalid OpenCode V2 CLI keybinds structure was accepted"
  else
    ok "invalid OpenCode V2 CLI keybinds structure fails"
  fi
  require_same_file "$malformed_before" "$malformed_config"
  require_contains "$malformed_log" "Expected 'keybinds' to be an object"

  rm -rf -- "$fixture_root"
}

test_learn_plugin_sync() {
  local fixture_root fixture_home remote source install_dir wrong_remote wrong_target invalid_target
  local stub_bin bun_log source_server
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  remote="$fixture_root/remote.git"
  source="$fixture_root/source"
  install_dir="$fixture_home/.local/share/opencode/learn"
  wrong_remote="$fixture_root/wrong.git"
  wrong_target="$fixture_root/wrong-target"
  invalid_target="$fixture_root/not-a-repository"
  stub_bin="$fixture_root/bin"
  bun_log="$fixture_root/bun.log"
  source_server="$source/src/server.ts"

  git init --bare "$remote" >/dev/null
  git init "$source" >/dev/null
  git -C "$source" branch -M main
  git -C "$source" config user.email fixture@example.invalid
  git -C "$source" config user.name fixture
  mkdir -p "$source/src"
  printf '%s\n' '{"name":"learn","version":"0.1.0"}' >"$source/package.json"
  printf '%s\n' 'lockfileVersion: 1' >"$source/bun.lock"
  printf '%s\n' 'node_modules/' >"$source/.gitignore"
  printf '%s\n' 'export const fixture = true' >"$source_server"
  printf '%s\n' 'export const fixture = true' >"$source/src/tui.ts"
  git -C "$source" add package.json bun.lock .gitignore src
  git -C "$source" commit -m fixture >/dev/null
  git -C "$source" remote add origin "$remote"
  git -C "$source" push -u origin main >/dev/null

  mkdir -p "$stub_bin"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf "%s\\n" "$PUPPETEER_SKIP_DOWNLOAD|$*" >>"$LEARN_BUN_LOG"' \
    'mkdir -p "$PWD/node_modules/@opencode-ai/plugin"' \
    'printf "%s\\n" "{}" >"$PWD/node_modules/@opencode-ai/plugin/package.json"' \
    >"$stub_bin/bun"
  chmod +x "$stub_bin/bun"

  if (
    HOME="$fixture_home"
    LEARN_REPOSITORY_URL="$remote"
    LEARN_INSTALL_DIR="$install_dir"
    PATH="$stub_bin:$PATH"
    export LEARN_BUN_LOG="$bun_log"
    source "$REPO_DIR/apply.sh"
    sync_learn_plugin
  ) >/dev/null 2>&1; then
    ok "Learn sync fixture clones and installs"
  else
    not_ok "Learn sync fixture failed to clone and install"
  fi
  require_file "$install_dir/package.json"
  require_file "$install_dir/src/server.ts"
  require_file "$install_dir/src/tui.ts"
  require_file "$install_dir/node_modules/@opencode-ai/plugin/package.json"
  require_text_count "$bun_log" "true|install --frozen-lockfile" "1"

  printf '%s\n' 'export const updated = true' >>"$source_server"
  git -C "$source" add src/server.ts
  git -C "$source" commit -m update >/dev/null
  git -C "$source" push origin main >/dev/null
  if (
    HOME="$fixture_home"
    LEARN_REPOSITORY_URL="$remote"
    LEARN_INSTALL_DIR="$install_dir"
    PATH="$stub_bin:$PATH"
    export LEARN_BUN_LOG="$bun_log"
    source "$REPO_DIR/apply.sh"
    sync_learn_plugin
  ) >/dev/null 2>&1; then
    ok "Learn sync fixture fast-forwards an existing checkout"
  else
    not_ok "Learn sync fixture failed to fast-forward an existing checkout"
  fi
  require_contains "$install_dir/src/server.ts" "export const updated = true"
  require_text_count "$bun_log" "true|install --frozen-lockfile" "2"

  printf '%s\n' 'local change' >>"$install_dir/src/server.ts"
  if (
    HOME="$fixture_home"
    LEARN_REPOSITORY_URL="$remote"
    LEARN_INSTALL_DIR="$install_dir"
    PATH="$stub_bin:$PATH"
    export LEARN_BUN_LOG="$bun_log"
    source "$REPO_DIR/apply.sh"
    sync_learn_plugin
  ) >/dev/null 2>&1; then
    not_ok "dirty Learn checkout was accepted"
  else
    ok "dirty Learn checkout is rejected"
  fi

  mkdir -p "$invalid_target"
  printf '%s\n' 'preserve me' >"$invalid_target/marker"
  if (
    HOME="$fixture_home"
    LEARN_REPOSITORY_URL="$remote"
    LEARN_INSTALL_DIR="$invalid_target"
    PATH="$stub_bin:$PATH"
    export LEARN_BUN_LOG="$bun_log"
    source "$REPO_DIR/apply.sh"
    sync_learn_plugin
  ) >/dev/null 2>&1; then
    not_ok "non-Git Learn target was accepted"
  else
    ok "non-Git Learn target is rejected"
  fi
  require_contains "$invalid_target/marker" "preserve me"

  git init --bare "$wrong_remote" >/dev/null
  git clone --quiet --branch main --single-branch "$remote" "$wrong_target"
  git -C "$wrong_target" remote set-url origin "$wrong_remote"
  if (
    HOME="$fixture_home"
    LEARN_REPOSITORY_URL="$remote"
    LEARN_INSTALL_DIR="$wrong_target"
    PATH="$stub_bin:$PATH"
    export LEARN_BUN_LOG="$bun_log"
    source "$REPO_DIR/apply.sh"
    sync_learn_plugin
  ) >/dev/null 2>&1; then
    not_ok "wrong Learn remote was accepted"
  else
    ok "wrong Learn remote is rejected"
  fi

  if (
    HOME="$fixture_home"
    LEARN_REPOSITORY_URL="$remote"
    LEARN_INSTALL_DIR="$source/src"
    PATH="$stub_bin:$PATH"
    export LEARN_BUN_LOG="$bun_log"
    source "$REPO_DIR/apply.sh"
    sync_learn_plugin
  ) >/dev/null 2>&1; then
    not_ok "nested Learn worktree path was accepted"
  else
    ok "nested Learn worktree path is rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_ai_memory_service_staleness() {
  local fixture_root fixture_home stub_bin env_file warn_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  env_file="$fixture_home/.config/ai-memory/env"
  warn_log="$fixture_root/warn.log"
  mkdir -p "$(dirname "$env_file")" "$stub_bin"

  # The env file the operator and the script own.
  printf '%s\n' \
    'AI_MEMORY_LLM_PROVIDER=opencode' \
    'AI_MEMORY_LLM_MODEL=muse-spark-1.3-contributor' >"$env_file"
  chmod 600 "$env_file"

  # launchctl supplies the pid, ps supplies the environment the process actually
  # runs with. The service execs through a shell that sources the env file, so
  # the file-injected variables are visible in the process environment only.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''    path = /Library/LaunchDaemons/ai-memory.plist\n    state = running\n    pid = 4242\n'\''' \
    >"$stub_bin/launchctl"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\'' 4242 /usr/local/bin/ai-memory --data-dir /data AI_MEMORY_LLM_PROVIDER=%s AI_MEMORY_LLM_MODEL=muse-spark-1.3-contributor\n'\'' "${STALE_PROVIDER:-opencode}"' \
    >"$stub_bin/ps"
  chmod +x "$stub_bin/launchctl" "$stub_bin/ps"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    warn_on_stale_ai_memory_service
  ) >"$warn_log" 2>&1; then
    if grep -q "stale\|restart" "$warn_log"; then
      not_ok "a service matching the environment file was reported as stale"
    else
      ok "a service matching the environment file is not reported as stale"
    fi
  else
    not_ok "staleness check failed on a matching service"
  fi

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    STALE_PROVIDER=zero-llm
    export HOME PATH STALE_PROVIDER
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    warn_on_stale_ai_memory_service
  ) >"$warn_log" 2>&1; then
    ok "a stale service is reported without failing apply"
    require_contains "$warn_log" "AI_MEMORY_LLM_PROVIDER"
    require_contains "$warn_log" "launchctl kickstart -k"
  else
    not_ok "a stale service failed apply instead of warning"
  fi

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    warn_on_stale_ai_memory_service
  ) >"$warn_log" 2>&1; then
    if [[ -s "$warn_log" ]]; then
      not_ok "the Linux host warned about a stale service"
    else
      ok "the Linux host skips the check, because it restarts unconditionally"
    fi
  else
    not_ok "the Linux staleness check failed"
  fi

  printf '%s\n' '#!/usr/bin/env bash' 'printf '\''    state = not running\n'\''' >"$stub_bin/launchctl"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    warn_on_stale_ai_memory_service
  ) >"$warn_log" 2>&1; then
    if grep -q "stale" "$warn_log"; then
      not_ok "a stopped service was reported as stale rather than stopped"
    else
      ok "a stopped service is not misreported as stale"
    fi
  else
    not_ok "the stopped-service check failed"
  fi

  rm -rf -- "$fixture_root"
}

test_ai_memory_token_delivery() {
  local fixture_root fixture_home stub_bin token_file env_file call_log profile
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  token_file="$fixture_home/.config/ai-memory/client-token"
  env_file="$fixture_home/.config/ai-memory/env"
  call_log="$fixture_root/calls.log"
  profile="$fixture_home/.bash_profile"
  mkdir -p "$(dirname "$token_file")" "$stub_bin" "$fixture_home/.config/opencode"
  printf '%s\n' 'fixture-token-value' >"$token_file"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$*" >>"$OPENCODE_TEST_CALL_LOG"' >"$stub_bin/ai-memory"
  chmod +x "$stub_bin/ai-memory"

  # A loopback server host still requires a bearer token, so the
  # hook configuration must receive it even though there is no remote URL.
  : >"$call_log"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    OPENCODE_TEST_CALL_LOG="$call_log"
    export HOME PATH OPENCODE_TEST_CALL_LOG
    source "$REPO_DIR/apply.sh"
    AI_MEMORY_SERVER_URL="$AI_MEMORY_LOOPBACK_SERVER_URL"
    wire_ai_memory_to_opencode
  ) >/dev/null 2>&1; then
    if grep -q -- "--auth-token fixture-token-value" "$call_log"; then
      ok "loopback ai-memory hook installation receives the bearer token"
    else
      not_ok "loopback ai-memory hook installation omitted the bearer token"
    fi
  else
    not_ok "loopback ai-memory hook installation failed"
  fi

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    configure_bash_login_env
  ) >/dev/null 2>&1; then
    require_contains "$profile" 'source "$HOME/.config/ai-memory/env"'
  else
    not_ok "macOS Bash profile setup failed for the ai-memory environment"
  fi

  rm -rf -- "$fixture_root"
}

test_ai_memory_env_file() {
  local fixture_root fixture_home fixture_env fixture_config env_before first_env
  local no_key_home no_key_env
  local selected_profile profile_home profile_env
  local invalid_profile invalid_index invalid_home invalid_env invalid_before invalid_log
  local auth_name auth_index env_auth_home config_auth_home
  local scheduler_line marker_line
  local scheduler_default_home scheduler_default_env
  local scheduler_migrate_home scheduler_migrate_env migrated_line migrated_marker
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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

  # A client must not carry a profile it does not own, and the retired subagent
  # selector must not linger anywhere, because a dead variable reads as live.
  # Reached through setup_ai_memory, the way apply.sh actually runs it, so this
  # fails if the client branch ever stops converging the file again.
  client_env_home="$fixture_root/client-env-home"
  client_env_file="$client_env_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$client_env_file")"
  printf '%s\n' \
    'OPENCODE_API_KEY=fixture-secret' \
    'DOTFILES_OPENCODE_SUBAGENT_PROFILE=openai-gpt-6-luna' \
    'DOTFILES_AI_MEMORY_LLM_ENABLED=false' \
    'DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-muse-spark-1.3-contributor' \
    'AI_MEMORY_LLM_PROVIDER=opencode' \
    'AI_MEMORY_LLM_MODEL=muse-spark-1.3-contributor' \
    'AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=true' >"$client_env_file"
  if (
    HOME="$client_env_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    # Sourcing apply.sh DEFINES these functions, so a stub declared before the
    # source is silently overwritten and the fixture runs the real code. Every
    # override therefore has to come after the source.
    agent_stack_platform() { printf '%s\n' Linux; }
    agent_stack_is_client_host() { return 0; }
    install_ai_memory_systemd_user_service() { :; }
    start_ai_memory_systemd_user_service() { :; }
    wire_ai_memory_to_opencode() { :; }
    # apply.sh derives AI_MEMORY_SERVER_URL at source time from the environment,
    # so the override has to be set here, after sourcing. Setting it before is
    # silently replaced by the loopback default.
    AI_MEMORY_SERVER_URL="https://server.example.test:8443"
    AI_MEMORY_LOOPBACK_SERVER_URL="http://127.0.0.1:49374"
    AI_MEMORY_AUTH_TOKEN_FILE="$client_env_home/.config/ai-memory/client-token"
    AI_MEMORY_AUTH_TOKEN="fixture-token"
    AI_MEMORY_CONFIG_FILE="$client_env_home/.config/ai-memory/config.toml"
    AI_MEMORY_DATA_DIR="$client_env_home/.local/share/ai-memory"
    OPENCODE_TEST_CALL_LOG="$fixture_root/client-wire.log"
    export AI_MEMORY_SERVER_URL AI_MEMORY_LOOPBACK_SERVER_URL
    export AI_MEMORY_AUTH_TOKEN_FILE AI_MEMORY_AUTH_TOKEN
    export AI_MEMORY_CONFIG_FILE AI_MEMORY_DATA_DIR OPENCODE_TEST_CALL_LOG
    setup_ai_memory
  ) >/dev/null 2>&1; then
    if grep -q 'DOTFILES_OPENCODE_SUBAGENT_PROFILE' "$client_env_file"; then
      not_ok "the retired subagent selector survived on a client"
    else
      ok "the retired subagent selector is removed everywhere"
    fi
    for governed in DOTFILES_AI_MEMORY_LLM_PROFILE AI_MEMORY_LLM_PROVIDER AI_MEMORY_LLM_MODEL; do
      if grep -q "^$governed=" "$client_env_file"; then
        not_ok "a client still carries $governed"
      else
        ok "a client carries no $governed"
      fi
    done
    require_env_assignment "$client_env_file" "OPENCODE_API_KEY" "fixture-secret"
    require_env_assignment "$client_env_file" "AGENTS_AI_MEMORY_LLM_ENABLED" "false"
    if grep -q '^DOTFILES_AI_MEMORY_LLM_ENABLED=' "$client_env_file"; then
      not_ok "the retired pause flag survived on a client"
    else
      ok "the retired pause flag migrates on a client"
    fi
    # Exactly one copy, not a duplicate above the marker plus one below it.
    if [[ "$(grep -c '^AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=' "$client_env_file")" -eq 1 ]]; then
      ok "the client approval flag appears exactly once"
    else
      not_ok "the client approval flag is duplicated"
    fi
  else
    not_ok "client environment fixture failed"
  fi

  # The scheduler flag is operator-owned. The fixture above sets it to true, and
  # the script must not silently rewrite it to false, because a value that looks
  # editable but is not is the same defect class as the ones already fixed.
  require_env_assignment "$fixture_env" "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED" "true"
  scheduler_line="$(grep -n 'AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED' "$fixture_env" | head -1 | cut -d: -f1)"
  marker_line="$(grep -n '^# Managed by guisaliba/agents apply.sh\.$' "$fixture_env" | head -1 | cut -d: -f1)"
  if [[ -n "$scheduler_line" && -n "$marker_line" && "$scheduler_line" -lt "$marker_line" ]]; then
    ok "the operator-owned scheduler flag sits above the managed block"
  else
    not_ok "the operator-owned scheduler flag is inside the managed block"
  fi
  if [[ "$(grep -c 'AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED' "$fixture_env")" -eq 1 ]]; then
    ok "the scheduler flag appears exactly once"
  else
    not_ok "the scheduler flag is duplicated"
  fi

  # Absent means the tool's own default, which is to schedule. That is not a safe
  # default for a paid model, so the script seeds a disabled value and then
  # respects whatever the operator changes it to.
  scheduler_default_home="$fixture_root/scheduler-default-home"
  scheduler_default_env="$scheduler_default_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$scheduler_default_env")"
  printf '%s\n' 'UNRELATED_SETTING=keep' >"$scheduler_default_env"
  if (
    HOME="$scheduler_default_home"
    source "$REPO_DIR/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    require_env_assignment "$scheduler_default_env" "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED" "false"
  else
    not_ok "seeding a disabled scheduler default failed"
  fi

  # A value the operator wrote below the managed marker is preserved and moved up,
  # so a flag written by an older apply.sh is not lost on the next run.
  scheduler_migrate_home="$fixture_root/scheduler-migrate-home"
  scheduler_migrate_env="$scheduler_migrate_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$scheduler_migrate_env")"
  printf '%s\n' \
    'UNRELATED_SETTING=keep' \
    '# Managed by guisalibaba/agents apply.sh.' \
    'AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED=true' \
    'AI_MEMORY_LLM_PROVIDER=stale' >"$scheduler_migrate_env"
  if (
    HOME="$scheduler_migrate_home"
    source "$REPO_DIR/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    require_env_assignment "$scheduler_migrate_env" "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED" "true"
    migrated_line="$(grep -n 'AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED' "$scheduler_migrate_env" | head -1 | cut -d: -f1)"
    migrated_marker="$(grep -n '^# Managed by guisaliba/agents apply.sh\.$' "$scheduler_migrate_env" | head -1 | cut -d: -f1)"
    if [[ -n "$migrated_line" && -n "$migrated_marker" && "$migrated_line" -lt "$migrated_marker" ]]; then
      ok "a scheduler flag below the marker is relocated above it"
    else
      not_ok "a scheduler flag below the marker was not relocated"
    fi
  else
    not_ok "migrating a scheduler flag from the managed block failed"
  fi

  # The DOTFILES_ pause flag is retired in favour of the agents-owned name.
  # An old checkout migrates its value, drops the old name, and drops the
  # stale dotfiles marker, which current apply.sh never wrote.
  migrate_home="$fixture_root/enabled-migrate-home"
  migrate_env="$migrate_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$migrate_env")"
  printf '%s\n' \
    '# Managed by dotfiles/agents/apply.sh.' \
    'DOTFILES_AI_MEMORY_LLM_ENABLED=false' \
    'UNRELATED_SETTING=keep' >"$migrate_env"
  if (
    HOME="$migrate_home"
    source "$REPO_DIR/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    require_env_assignment "$migrate_env" "AGENTS_AI_MEMORY_LLM_ENABLED" "false"
  else
    not_ok "migrating the retired pause flag failed"
  fi
  if grep -q 'DOTFILES_AI_MEMORY_LLM_ENABLED' "$migrate_env"; then
    not_ok "the retired pause flag survived migration"
  else
    ok "the retired pause flag is removed"
  fi
  if grep -q 'Managed by dotfiles/agents/apply.sh' "$migrate_env"; then
    not_ok "the stale dotfiles marker survived"
  else
    ok "the stale dotfiles marker is removed"
  fi

  no_key_home="$fixture_root/no-key-home"
  no_key_env="$no_key_home/.config/ai-memory/env"
  mkdir -p "$(dirname "$no_key_env")"
  printf '%s\n' 'UNRELATED_SETTING=keep' >"$no_key_env"
  if (
    HOME="$no_key_home"
    source "$REPO_DIR/apply.sh"
    configure_ai_memory_env_file
  ) >/dev/null 2>&1; then
    ok "default DeepSeek v4.1 Flash profile stays disabled without its API key"
  else
    not_ok "default DeepSeek v4.1 Flash zero-LLM fixture failed"
  fi
  require_env_assignment "$no_key_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "$AI_MEMORY_LLM_PROFILE_EXPECTED"
  require_env_assignment "$no_key_env" "AI_MEMORY_LLM_PROVIDER" ""
  require_env_assignment "$no_key_env" "AI_MEMORY_LLM_MODEL" "$AI_MEMORY_LLM_MODEL_EXPECTED"

  for selected_profile in $(profile_names); do
    profile_home="$fixture_root/profile-home-$selected_profile"
    profile_env="$profile_home/.config/ai-memory/env"
    mkdir -p "$(dirname "$profile_env")"
    printf '%s\n' \
      "DOTFILES_AI_MEMORY_LLM_PROFILE=$selected_profile" \
      'OPENCODE_API_KEY=fixture-secret' >"$profile_env"
    if (
      HOME="$profile_home"
      source "$REPO_DIR/apply.sh"
      configure_ai_memory_env_file
    ) >/dev/null 2>&1; then
      ok "OpenCode Go profile enables with its separate key: $selected_profile"
    else
      not_ok "OpenCode Go profile fixture failed: $selected_profile"
    fi
    require_env_assignment "$profile_env" "DOTFILES_AI_MEMORY_LLM_PROFILE" "$selected_profile"
    require_env_assignment "$profile_env" "OPENCODE_API_KEY" "fixture-secret"
    require_env_assignment "$profile_env" "AI_MEMORY_LLM_PROVIDER" "$(profile_field "$selected_profile" provider)"
    require_env_assignment "$profile_env" "AI_MEMORY_LLM_MODEL" "$(profile_field "$selected_profile" model)"
  done

  invalid_index=0
  for invalid_profile in openai-subscription-luna openai-api-luna disabled not-a-profile opencode-go-deepseek opencode-go-muse; do
    invalid_index=$((invalid_index + 1))
    invalid_home="$fixture_root/invalid-profile-home-$invalid_index"
    invalid_env="$invalid_home/.config/ai-memory/env"
    invalid_before="$fixture_root/invalid-profile-before-$invalid_index"
    invalid_log="$fixture_root/invalid-profile-$invalid_index.log"
    mkdir -p "$(dirname "$invalid_env")"
    printf '%s\n' \
      'UNRELATED_SETTING=keep' \
      "DOTFILES_AI_MEMORY_LLM_PROFILE=$invalid_profile" >"$invalid_env"
    cp "$invalid_env" "$invalid_before"
    if (
      HOME="$invalid_home"
      source "$REPO_DIR/apply.sh"
      configure_ai_memory_env_file
    ) >"$invalid_log" 2>&1; then
      not_ok "unsupported ai-memory profile $invalid_profile was accepted"
    else
      ok "unsupported ai-memory profile $invalid_profile fails safely"
    fi
    require_same_file "$invalid_before" "$invalid_env"
    require_contains "$invalid_log" "Unsupported DOTFILES_AI_MEMORY_LLM_PROFILE"
  done

  if (
    HOME="$fixture_home"
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    verify_ai_memory_unauthenticated_loopback
  ) >/dev/null 2>&1; then
    ok "ai-memory default auth files allow unauthenticated loopback"
  else
    not_ok "ai-memory default auth files were rejected"
  fi

  # A client host is not loopback. It talks to a remote server and therefore
  # needs a bearer token, but the old client branch demanded an unauthenticated
  # policy and forbade the token the CLI requires. Branch on the server URL so
  # each host role is checked against the policy that role actually has.
  client_auth_home="$fixture_root/client-auth-home"
  mkdir -p "$client_auth_home/.config/ai-memory"
  if (
    HOME="$client_auth_home"
    AI_MEMORY_SERVER_URL="https://server.example.test:8443"
    AI_MEMORY_AUTH_TOKEN="fixture-token"
    export AI_MEMORY_SERVER_URL AI_MEMORY_AUTH_TOKEN
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    verify_ai_memory_unauthenticated_loopback
  ) >/dev/null 2>&1; then
    ok "client host accepts a bearer token in the shell"
  else
    not_ok "client host rejected a bearer token in the shell"
  fi

  client_env_home="$fixture_root/client-env-home"
  mkdir -p "$client_env_home/.config/ai-memory"
  printf '%s\n' 'AI_MEMORY_AUTH_TOKEN=fixture-token' >"$client_env_home/.config/ai-memory/env"
  if (
    HOME="$client_env_home"
    AI_MEMORY_SERVER_URL="https://server.example.test:8443"
    export AI_MEMORY_SERVER_URL
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    verify_ai_memory_unauthenticated_loopback
  ) >/dev/null 2>&1; then
    ok "client host accepts a bearer token in the environment file"
  else
    not_ok "client host rejected a bearer token in the environment file"
  fi

  client_notoken_home="$fixture_root/client-notoken-home"
  mkdir -p "$client_notoken_home/.config/ai-memory"
  if (
    HOME="$client_notoken_home"
    AI_MEMORY_SERVER_URL="https://server.example.test:8443"
    export AI_MEMORY_SERVER_URL
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    verify_ai_memory_unauthenticated_loopback
  ) >"$fixture_root/client-notoken.log" 2>&1; then
    not_ok "client host without any token was accepted"
  else
    ok "client host without any token is rejected"
  fi
  require_contains "$fixture_root/client-notoken.log" "client"

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
      source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
    verify_ai_memory_no_static_auth_files
  ) >/dev/null 2>&1; then
    not_ok "ai-memory config bearer token was accepted"
  else
    ok "ai-memory config bearer token is rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_agent_stack_helpers() {
  local fixture_root fixture_home fixture_env fixture_token fixture_config
  local real_target atomic_target atomic_expected malformed_manifest duplicate_manifest
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_env="$fixture_home/.config/ai-memory/env"
  fixture_token="$fixture_home/.config/opencode/secrets/github-mcp-pat"
  fixture_config="$fixture_home/.config/ai-memory/config.toml"
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
    initialize_ai_memory
  ) >/dev/null 2>&1; then
    not_ok "ai-memory config symlink was accepted"
  else
    ok "ai-memory config symlink is rejected before initialization"
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
  printf '%s\n' $'local\tduplicate\tskills/find-skills\tno' >>"$duplicate_manifest"
  if python3 "$AGENT_STACK_HELPER" manifest "$duplicate_manifest" >/dev/null 2>&1; then
    not_ok "duplicate skill manifest name was accepted"
  else
    ok "duplicate skill manifest name is rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_macos_platform_prerequisites() {
  local fixture_root fixture_home stub_bin brew_prefix install_log expected_log expected_path
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  brew_prefix="$fixture_root/homebrew"
  install_log="$fixture_root/brew-install.log"
  expected_log="$fixture_root/expected.log"
  mkdir -p "$fixture_home" "$stub_bin" "$brew_prefix/bin"
  : >"$install_log"

  printf '%s\n' \
    '#!/bin/bash' \
    '[[ "${1:-}" == -s ]] && { printf '\''Darwin\n'\''; exit 0; }' \
    'exit 2' >"$stub_bin/uname"
  printf '%s\n' \
    '#!/bin/bash' \
    'if [[ "${1:-}" == --prefix ]]; then printf '\''%s\n'\'' "$MACOS_TEST_BREW_PREFIX"; exit 0; fi' \
    'printf '\''%s\n'\'' "$*" >>"$MACOS_TEST_INSTALL_LOG"' \
    'case "$*" in' \
    '  "install bash") printf '\''#!/bin/bash\nexit 0\n'\'' >"$MACOS_TEST_BREW_PREFIX/bin/bash" ;;' \
    '  "install python") printf '\''#!/bin/bash\nexit 0\n'\'' >"$MACOS_TEST_BREW_PREFIX/bin/python3" ;;' \
    '  "install --cask google-chrome") mkdir -p "$GOOGLE_CHROME_APP_PATH_MACOS"; exit 0 ;;' \
    '  *) exit 2 ;;' \
    'esac' \
    'chmod +x "$MACOS_TEST_BREW_PREFIX/bin/${2/python/python3}"' >"$stub_bin/brew"
  chmod +x "$stub_bin/uname" "$stub_bin/brew"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:$brew_prefix/bin:/bin"
    MACOS_TEST_BREW_PREFIX="$brew_prefix"
    MACOS_TEST_INSTALL_LOG="$install_log"
    GOOGLE_CHROME_APP_PATH_MACOS="$fixture_root/Applications/Google Chrome.app"
    export HOME PATH MACOS_TEST_BREW_PREFIX MACOS_TEST_INSTALL_LOG GOOGLE_CHROME_APP_PATH_MACOS
    source "$REPO_DIR/apply.sh"
    prepare_platform_prerequisites
    prepare_platform_prerequisites
    prepare_full_stack_prerequisites
    prepare_full_stack_prerequisites
    expected_path="$fixture_home/.opencode/bin:$fixture_home/.local/bin:$fixture_home/bin:$brew_prefix/bin:"
    [[ "$PATH" == "$expected_path"* ]]
  ) >/dev/null 2>&1; then
    ok "macOS platform prerequisites install and select Homebrew tools"
  else
    not_ok "macOS platform prerequisites did not install and select Homebrew tools"
  fi
  printf '%s\n' 'install bash' 'install python' 'install --cask google-chrome' >"$expected_log"
  require_same_file "$expected_log" "$install_log"

  if (
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    have() { [[ "$1" != systemctl ]]; }
    check_prerequisites
  ) >/dev/null 2>&1; then
    ok "macOS prerequisite validation does not require systemd"
  else
    not_ok "macOS prerequisite validation still requires a Linux command"
  fi

  if (
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    have() { [[ "$1" != systemctl ]]; }
    check_prerequisites
  ) >/dev/null 2>&1; then
    not_ok "Linux prerequisite validation accepted missing systemd"
  else
    ok "Linux prerequisite validation still requires systemd"
  fi

  rm -rf -- "$fixture_root"
}

test_apply_scope() {
  local fixture_root action_log expected_log
  fixture_root="$(mktemp -d)"
  action_log="$fixture_root/actions.log"
  expected_log="$fixture_root/expected.log"

  if (
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    prepare_platform_prerequisites() { printf 'platform:%s\n' "$(agent_stack_platform)" >>"$action_log"; }
    prepare_full_stack_prerequisites() { printf 'full:%s\n' "$(agent_stack_platform)" >>"$action_log"; }
    check_prerequisites() { printf '%s\n' prerequisites >>"$action_log"; }
    require_minimum_version() { printf 'version:%s\n' "$1" >>"$action_log"; }
    install_opencode() { printf '%s\n' opencode-binary >>"$action_log"; }
    install_ai_memory() { printf '%s\n' ai-memory-binary >>"$action_log"; }
    report_optional_ai_jail() { printf '%s\n' ai-jail >>"$action_log"; }
    verify_ai_memory_unauthenticated_loopback() { printf '%s\n' loopback >>"$action_log"; }
    setup_opencode() { printf '%s\n' opencode-config >>"$action_log"; }
    setup_ai_memory() { printf '%s\n' ai-memory-config >>"$action_log"; }
    start_opencode_server() { printf '%s\n' server >>"$action_log"; }
    merge_opencode_shell_override() { printf '%s\n' shell >>"$action_log"; }
    configure_bash_login_env() { printf '%s\n' bash-profile >>"$action_log"; }
    install_plugins() { printf '%s\n' plugins >>"$action_log"; }
    install_required_skills() { printf '%s\n' skills >>"$action_log"; }
    main
  ) >/dev/null 2>&1; then
    ok "normal apply runs each setup stage"
  else
    not_ok "normal apply order fixture failed"
  fi
  printf '%s\n' \
    platform:Darwin \
    full:Darwin \
    prerequisites \
    version:bun \
    opencode-binary \
    ai-memory-binary \
    ai-jail \
    loopback \
    opencode-config \
    ai-memory-config \
    plugins \
    server \
    shell \
    bash-profile \
    skills >"$expected_log"
  require_same_file "$expected_log" "$action_log"

  rm -rf -- "$fixture_root"
}

test_rtk_plugin_installation() {
  local fixture_root fixture_home plugin_dir plugin_target plugin_config stub_bin rtk_log backup_dir
  local first_backup_count second_backup_count backup_file
  local -a backups=() rtk_entries=()
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  plugin_dir="$fixture_home/.config/opencode/plugins"
  plugin_target="$plugin_dir/rtk.ts"
  plugin_config="$fixture_home/.config/opencode/opencode.json"
  stub_bin="$fixture_root/bin"
  rtk_log="$fixture_root/rtk.log"
  backup_dir="$fixture_home/.local/share/opencode/plugin-backups"
  mkdir -p "$plugin_dir" "$stub_bin"
  printf '%s\n' 'legacy RTK V1 plugin' >"$plugin_target"
  printf '%s\n' 'export default { id: "other-plugin" }' >"$plugin_dir/other.ts"
  printf '%s\n' '{"plugins":["unrelated-plugin","rtk"]}' >"$plugin_config"
  cat >"$stub_bin/rtk" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RTK_TEST_LOG"
case "${1:-}" in
  --version) printf '%s\n' 'rtk 0.38.0' ;;
  rewrite)
    [[ "${2:-}" == 'git status --short' ]] || exit 8
    printf '%s' 'rtk git status --short'
    exit 3
    ;;
  gain) ;;
  init) printf '%s\n' 'official init must not run' >>"$RTK_TEST_LOG" ;;
  *) exit 9 ;;
esac
SH
  chmod +x "$stub_bin/rtk"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:$PATH"
    RTK_TEST_LOG="$rtk_log"
    export HOME PATH RTK_TEST_LOG
    unset RTK_VERSION RTK_BIN
    source "$REPO_DIR/apply.sh"
    install_plannotator() { :; }
    setup_opencode
    install_plugins
    [[ "$RTK_VERSION" == v0.50.0 ]]
  ) >/dev/null 2>&1; then
    ok "normal OpenCode setup and plugin installation install the pinned RTK payload"
  else
    not_ok "normal OpenCode setup and plugin installation did not install RTK"
  fi

  require_same_file "$REPO_DIR/plugins/rtk/rtk.ts" "$plugin_target"
  require_file "$plugin_dir/other.ts"
  shopt -s nullglob
  rtk_entries=("$plugin_dir"/rtk* "$plugin_dir"/.rtk*)
  shopt -u nullglob
  if [[ ${#rtk_entries[@]} -eq 1 && "${rtk_entries[0]}" == "$plugin_target" ]]; then
    ok "RTK install leaves one local RTK plugin and no discovery backup"
  else
    not_ok "RTK install left a second local RTK plugin"
  fi
  if [[ -d "$backup_dir" ]]; then
    shopt -s nullglob
    backups=("$backup_dir"/rtk.ts.*)
    shopt -u nullglob
  fi
  if [[ ${#backups[@]} -eq 1 ]]; then
    backup_file="${backups[0]}"
    if [[ "${backup_file%/*}" == "$backup_dir" ]] && \
      grep -q 'legacy RTK V1 plugin' "$backup_file"; then
      ok "legacy RTK content is backed up outside the plugin discovery directory"
    else
      not_ok "legacy RTK backup is not safe or does not preserve the old content"
    fi
  else
    not_ok "expected one backup of the replaced RTK plugin, found ${#backups[@]}"
  fi
  if grep -q '^init' "$rtk_log"; then
    not_ok "apply invoked RTK's legacy OpenCode plugin generator"
  else
    ok "apply verifies the RTK CLI without running the legacy plugin generator"
  fi
  if grep -q '^rewrite git status --short$' "$rtk_log"; then
    ok "apply validates installed RTK rewrite behavior"
  else
    not_ok "apply did not validate the installed RTK rewrite behavior"
  fi

  first_backup_count="${#backups[@]}"
  chmod 0666 "$plugin_target"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:$PATH"
    RTK_TEST_LOG="$rtk_log"
    export HOME PATH RTK_TEST_LOG
    unset RTK_VERSION RTK_BIN
    source "$REPO_DIR/apply.sh"
    install_plannotator() { :; }
    setup_opencode
    install_plugins
  ) >/dev/null 2>&1; then
    ok "RTK plugin setup succeeds on a repeat apply"
  else
    not_ok "RTK plugin setup failed on a repeat apply"
  fi
  shopt -s nullglob
  backups=("$backup_dir"/rtk.ts.*)
  shopt -u nullglob
  second_backup_count="${#backups[@]}"
  if [[ "$first_backup_count" == "$second_backup_count" ]]; then
    ok "repeat apply does not create another legacy RTK backup"
  else
    not_ok "repeat apply created an extra RTK backup"
  fi
  require_same_file "$REPO_DIR/plugins/rtk/rtk.ts" "$plugin_target"
  require_file_mode "$plugin_target" "644"

  rm -rf -- "$fixture_root"
}

test_rtk_unsafe_target_handling() {
  local fixture_root symlink_home symlink_plugins symlink_target sentinel external_dir
  local directory_home directory_plugins directory_target
  fixture_root="$(mktemp -d)"
  symlink_home="$fixture_root/symlink-home"
  symlink_plugins="$symlink_home/.config/opencode/plugins"
  symlink_target="$symlink_plugins/rtk.ts"
  sentinel="$fixture_root/sentinel"
  external_dir="$fixture_root/external-plugins"
  directory_home="$fixture_root/directory-home"
  directory_plugins="$directory_home/.config/opencode/plugins"
  directory_target="$directory_plugins/rtk.ts"

  mkdir -p "$symlink_plugins" "$external_dir" "$directory_target"
  printf '%s\n' 'do not replace this file' >"$sentinel"
  ln -s "$sentinel" "$symlink_target"
  if (
    HOME="$symlink_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted a symlink target"
  else
    ok "RTK installer rejects a symlink target"
  fi
  require_file_content "$sentinel" "do not replace this file"

  if (
    HOME="$directory_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted a directory target"
  else
    ok "RTK installer rejects a directory target"
  fi

  rmdir "$directory_target" "$directory_plugins"
  ln -s "$external_dir" "$directory_plugins"
  if (
    HOME="$directory_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted a symlink plugin directory"
  else
    ok "RTK installer rejects a symlink plugin directory"
  fi
  if [[ ! -e "$external_dir/rtk.ts" ]]; then
    ok "RTK installer does not write through a plugin-directory symlink"
  else
    not_ok "RTK installer wrote through a plugin-directory symlink"
  fi

  rm -rf -- "$fixture_root"
}

test_rtk_duplicate_local_plugin_handling() {
  local fixture_root fixture_home plugin_dir target duplicate package_dir exports_package_dir
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  plugin_dir="$fixture_home/.config/opencode/plugins"
  target="$plugin_dir/rtk.ts"
  duplicate="$plugin_dir/custom-plugin.ts"
  package_dir="$plugin_dir/custom-package"
  mkdir -p "$plugin_dir"

  printf '%s\n' 'export default { id: "rtk" }' >"$duplicate"
  if (
    HOME="$fixture_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted another local file with id rtk"
  else
    ok "RTK installer rejects another local file with id rtk"
  fi
  [[ ! -e "$target" ]] && ok "RTK installer preserves the conflicting local plugin" || \
    not_ok "RTK installer wrote over a conflicting local plugin"

  printf '%s\n' 'const id = "rtk"; export default { id }' >"$duplicate"
  if (
    HOME="$fixture_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted a local plugin with shorthand id rtk"
  else
    ok "RTK installer rejects a local plugin with shorthand id rtk"
  fi
  [[ ! -e "$target" ]] && ok "RTK installer preserves the shorthand-ID plugin" || \
    not_ok "RTK installer wrote over the shorthand-ID plugin"
  rm -f "$target"

  rm -f "$duplicate"
  mkdir -p "$package_dir"
  printf '%s\n' '{"name":"other-package","main":"index.js"}' >"$package_dir/package.json"
  printf '%s\n' 'export default { id: "rtk" }' >"$package_dir/index.js"
  if (
    HOME="$fixture_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted a package entry with id rtk"
  else
    ok "RTK installer rejects a package entry with id rtk"
  fi
  [[ ! -e "$target" ]] && ok "RTK installer preserves the conflicting plugin package" || \
    not_ok "RTK installer wrote over a conflicting plugin package"

  rm -rf -- "$package_dir"
  exports_package_dir="$plugin_dir/exports-package"
  mkdir -p "$exports_package_dir/src"
  printf '%s\n' '{"name":"exports-package","exports":{".":"./src/index.ts"}}' >"$exports_package_dir/package.json"
  printf '%s\n' 'export default { id: "rtk" }' >"$exports_package_dir/src/index.ts"
  if (
    HOME="$fixture_home"
    export HOME
    source "$REPO_DIR/apply.sh"
    install_rtk_plugin
  ) >/dev/null 2>&1; then
    not_ok "RTK installer accepted a package exports entry with id rtk"
  else
    ok "RTK installer rejects an exports-only package entry with id rtk"
  fi
  [[ ! -e "$target" ]] && ok "RTK installer preserves the exports-only plugin package" || \
    not_ok "RTK installer wrote over an exports-only plugin package"

  rm -rf -- "$fixture_root"
}

test_rtk_cli_compatibility_ignores_user_policy() {
  local fixture_root fixture_home policy_project stub_bin curl_log rtk_log
  local rewrite_output rewrite_exit bad_exit
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  policy_project="$fixture_root/project"
  stub_bin="$fixture_root/bin"
  curl_log="$fixture_root/curl.log"
  rtk_log="$fixture_root/rtk.log"
  mkdir -p "$fixture_home/.claude" "$policy_project/.claude" "$stub_bin"
  printf '%s\n' '{"permissions":{"deny":["Bash(git status --short)"]}}' \
    >"$fixture_home/.claude/settings.json"
  printf '%s\n' '{"permissions":{"deny":["Bash(git status --short)"]}}' \
    >"$policy_project/.claude/settings.json"
  cat >"$stub_bin/rtk" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*|$HOME|$PWD|${CLAUDE_CONFIG_DIR:-}" >>"$RTK_TEST_LOG"
case "${1:-}" in
  --version) printf '%s\n' 'rtk 0.38.0' ;;
  rewrite)
    if [[ "$HOME" == "$RTK_POLICY_HOME" || "$PWD" == "$RTK_POLICY_CWD" ]]; then
      printf '%s' 'policy denied'
      exit 2
    fi
    if [[ -n "${RTK_TEST_BAD_REWRITE_EXIT:-}" ]]; then
      printf '%s' 'warning: rewrite unavailable'
      exit "$RTK_TEST_BAD_REWRITE_EXIT"
    fi
    [[ "${CLAUDE_CONFIG_DIR:-}" == "$HOME/.claude" ]] || exit 8
    printf '%s' 'rtk git status --short'
    exit 3
    ;;
  gain) ;;
  *) exit 9 ;;
esac
SH
  cat >"$stub_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RTK_CURL_LOG"
exit 9
SH
  chmod +x "$stub_bin/rtk" "$stub_bin/curl"
  : >"$curl_log"

  if rewrite_output="$(
    cd "$policy_project"
    HOME="$fixture_home" \
      RTK_POLICY_HOME="$fixture_home" \
      RTK_POLICY_CWD="$policy_project" \
      PATH="$stub_bin:/usr/bin:/bin" \
      RTK_TEST_LOG="$rtk_log" \
      rtk rewrite 'git status --short' 2>/dev/null
  )"; then
    not_ok "fixture RTK permission rule did not deny the policy command"
  else
    rewrite_exit=$?
    if [[ "$rewrite_exit" == 2 ]]; then
      ok "fixture RTK permission rule returns deny exit code 2"
    else
      not_ok "fixture RTK permission rule returned exit code $rewrite_exit, not 2"
    fi
  fi

  if (
    cd "$policy_project"
    HOME="$fixture_home"
    RTK_POLICY_HOME="$fixture_home"
    RTK_POLICY_CWD="$policy_project"
    PATH="$stub_bin:/usr/bin:/bin"
    RTK_TEST_LOG="$rtk_log"
    RTK_CURL_LOG="$curl_log"
    export HOME RTK_POLICY_HOME RTK_POLICY_CWD PATH RTK_TEST_LOG RTK_CURL_LOG
    unset RTK_VERSION RTK_BIN
    source "$REPO_DIR/apply.sh"
    install_rtk
  ) >/dev/null 2>&1; then
    ok "apply keeps a compatible RTK CLI when user policy denies the probe command"
  else
    not_ok "user RTK policy made apply reject or reinstall a compatible CLI"
  fi
  require_empty_file "$curl_log"

  for bad_exit in 0 3; do
    if (
      cd "$policy_project"
      HOME="$fixture_home"
      RTK_TEST_BAD_REWRITE_EXIT="$bad_exit"
      RTK_TEST_LOG="$rtk_log"
      PATH="$stub_bin:/usr/bin:/bin"
      export HOME RTK_TEST_BAD_REWRITE_EXIT RTK_TEST_LOG PATH
      source "$REPO_DIR/apply.sh"
      ! rtk_cli_is_compatible
    ) >/dev/null 2>&1; then
      ok "apply rejects warning rewrite output with exit $bad_exit"
    else
      not_ok "apply accepted warning rewrite output with exit $bad_exit"
    fi
  done

  rm -rf -- "$fixture_root"
}

test_rtk_cli_installation() {
  local fixture_root fixture_home stub_bin curl_log rtk_log invalid_version apply_log plugin_target
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  curl_log="$fixture_root/curl.log"
  rtk_log="$fixture_root/rtk.log"
  apply_log="$fixture_root/apply.log"
  mkdir -p "$fixture_home" "$stub_bin"
  plugin_target="$fixture_home/.config/opencode/plugins/rtk.ts"
  mkdir -p "${plugin_target%/*}"
  cp "$REPO_DIR/plugins/rtk/rtk.ts" "$plugin_target"
  cat >"$stub_bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$RTK_CURL_LOG"
cat <<'INSTALLER'
[ "$RTK_VERSION" = "v0.50.0" ] || exit 10
mkdir -p "$HOME/.local/bin"
cat >"$HOME/.local/bin/rtk" <<'RTK'
#!/bin/sh
printf '%s\n' "$*" >>"$RTK_TEST_LOG"
case "${1:-}" in
  --version) printf '%s\n' 'rtk 0.50.0' ;;
  rewrite)
    [ "${2:-}" = 'git status --short' ] || exit 8
    printf '%s' 'rtk git status --short'
    exit 3
    ;;
  gain) ;;
  init) printf '%s\n' 'official init must not run' >>"$RTK_TEST_LOG" ;;
  *) exit 9 ;;
esac
RTK
chmod +x "$HOME/.local/bin/rtk"
INSTALLER
SH
  chmod +x "$stub_bin/curl"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    RTK_CURL_LOG="$curl_log"
    RTK_TEST_LOG="$rtk_log"
    export HOME PATH RTK_CURL_LOG RTK_TEST_LOG
    unset RTK_VERSION RTK_BIN
    source "$REPO_DIR/apply.sh"
    have() {
      if [[ "$1" == rtk ]]; then
        [[ -x "$HOME/.local/bin/rtk" ]]
      else
        command -v "$1" >/dev/null 2>&1
      fi
    }
    install_rtk
    install_rtk_plugin
    [[ "$RTK_VERSION" == v0.50.0 ]]
  ) >"$apply_log" 2>&1; then
    ok "fresh RTK installation uses the pinned stable CLI"
  else
    not_ok "fresh RTK installation did not use the pinned stable CLI"
  fi
  require_executable "$fixture_home/.local/bin/rtk"
  require_same_file "$REPO_DIR/plugins/rtk/rtk.ts" "$plugin_target"
  require_contains "$apply_log" "reload any running OpenCode process"
  if [[ ! -e "$fixture_home/.local/share/opencode/plugin-backups" ]]; then
    ok "identical RTK plugin content is not backed up again"
  else
    not_ok "identical RTK plugin content created an unnecessary backup"
  fi
  require_contains "$curl_log" "https://raw.githubusercontent.com/rtk-ai/rtk/v0.50.0/install.sh"
  require_contains "$rtk_log" "rewrite git status --short"
  if grep -q '^init$' "$rtk_log"; then
    not_ok "fresh RTK installation ran the legacy OpenCode plugin generator"
  else
    ok "fresh RTK installation does not generate a legacy OpenCode plugin"
  fi

  for invalid_version in main v0.51.0-rc.1; do
    : >"$curl_log"
    if (
      HOME="$fixture_root/invalid-home"
      PATH="$stub_bin:/usr/bin:/bin"
      RTK_CURL_LOG="$curl_log"
      RTK_TEST_LOG="$rtk_log"
      RTK_VERSION="$invalid_version"
      export HOME PATH RTK_CURL_LOG RTK_TEST_LOG RTK_VERSION
      mkdir -p "$HOME"
      source "$REPO_DIR/apply.sh"
      have() {
        if [[ "$1" == rtk ]]; then
          [[ -x "$HOME/.local/bin/rtk" ]]
        else
          command -v "$1" >/dev/null 2>&1
        fi
      }
      install_rtk
    ) >/dev/null 2>&1; then
      not_ok "fresh RTK installation accepted an unstable version tag: $invalid_version"
    else
      ok "fresh RTK installation rejects unstable version tag: $invalid_version"
    fi
    require_empty_file "$curl_log"
  done

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
    source "$REPO_DIR/apply.sh"
    install_required_skills
  ) >/dev/null 2>&1; then
    ok "manifest-driven skill installation applies"
  else
    not_ok "manifest-driven skill installation failed"
  fi
  require_dir "$fixture_home/.agents/skills/find-skills"
  require_dir "$fixture_home/.agents/skills/auto-pr-review"
  require_dir "$fixture_home/.agents/skills/daily-tasks"
  require_file "$fixture_home/.agents/skills/daily-tasks/SKILL.md"
  require_executable "$fixture_home/.agents/skills/daily-tasks/scripts/journal-task-sync"
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
    '-y skills add mattpocock/skills@engineering/codebase-design -g -a opencode -s codebase-design -y --copy' \
    '-y skills add mattpocock/skills@engineering/domain-modeling -g -a opencode -s domain-modeling -y --copy' \
    '-y skills add mattpocock/skills@productivity/grill-me -g -a opencode -s grill-me -y --copy' \
    '-y skills add mattpocock/skills@engineering/grill-with-docs -g -a opencode -s grill-with-docs -y --copy' \
    '-y skills add mattpocock/skills@productivity/grilling -g -a opencode -s grilling -y --copy' \
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

test_daily_task_sync() {
  if python3 "$REPO_DIR/skills/daily-tasks/tests/test_journal_task_sync.py"; then
    ok "daily task sync integration tests pass"
  else
    not_ok "daily task sync integration tests failed"
  fi
}

test_opencode_shell_override() {
  local fixture_root fixture_home aliases first_aliases stub_bin rtk_path_home rtk_conflict_bin
  local ai_memory_log raw_log expected yolo_log managed_rc token_log
  local server_host server_stub token_home token_stub
  local malformed_home malformed_aliases malformed_before malformed_log
  local temp_source_home temp_source temp_source_aliases temp_source_first
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  aliases="$fixture_home/.bash_aliases"
  first_aliases="$fixture_root/first-bash-aliases"
  stub_bin="$fixture_root/bin"
  ai_memory_log="$fixture_root/ai-memory.log"
  token_log="$fixture_root/token.log"
  raw_log="$fixture_root/raw-opencode.log"
  expected="$fixture_root/expected.log"
  yolo_log="$fixture_root/yolo.log"

  mkdir -p "$fixture_home/.opencode/bin" "$stub_bin"
  printf '%s\n' \
    'alias preserved-alias='\''printf preserved'\''' \
    '# >>> dotfiles OpenCode ai-memory wrapper >>>' \
    'alias opencode='\''stale-wrapper'\''' \
    '# <<< dotfiles OpenCode ai-memory wrapper <<<' >"$aliases"

  if (
    HOME="$fixture_home"
    source "$REPO_DIR/apply.sh"
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
  require_contains "$aliases" 'command ai-memory run opencode2 --executable "$HOME/.opencode/bin/opencode"'
  require_contains "$aliases" '--standalone'
  # The TUI must never attach to the shared daemon. That path loses
  # AI_MEMORY_RUN_ID and breaks handoff delivery.
  # The token must be read by the wrapper itself, not only by a login shell.
  require_contains "$aliases" 'AI_MEMORY_AUTH_TOKEN='

  # A non-login shell, or any process that did not pass through the profile,
  # must still authenticate. Drive the wrapper with the token deliberately unset
  # and the env file present, and require that the CLI call carries it.
  : >"$ai_memory_log"
  : >"$token_log"
  token_home="$fixture_root/token-home"
  token_stub="$fixture_root/token-bin"
  mkdir -p "$token_home/projects/agents" "$token_home/.config/ai-memory" \
    "$token_home/.opencode/bin" "$token_stub"
  printf '%s\n' 'AI_MEMORY_AUTH_TOKEN="fixture-bearer-token"' \
    >"$token_home/.config/ai-memory/env"
  chmod 600 "$token_home/.config/ai-memory/env"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_AI_MEMORY_LOG"' \
    'printf '\''%s\n'\'' "${AI_MEMORY_AUTH_TOKEN:-}" >"$OPENCODE_TEST_TOKEN_LOG"' \
    >"$token_stub/ai-memory"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_RAW_LOG"' >"$token_home/.opencode/bin/opencode"
  chmod +x "$token_stub/ai-memory" "$token_home/.opencode/bin/opencode"
  cp "$aliases" "$token_home/.bash_aliases"
  if (
    cd "$token_home/projects/agents"
    HOME="$token_home" \
      PATH="$token_stub:/usr/bin:/bin" \
      OPENCODE_SERVER_ENABLED=true \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      OPENCODE_TEST_RAW_LOG="$raw_log" \
      OPENCODE_TEST_TOKEN_LOG="$token_log" \
      env -u AI_MEMORY_AUTH_TOKEN \
      bash --noprofile --norc -c \
        'source "$HOME/.bash_aliases"; opencode'
  ); then
    require_file_content "$token_log" "fixture-bearer-token"
  else
    not_ok "the wrapper failed with the token unset in the shell"
  fi

  # An explicit export must win, so an operator override is never overwritten.
  : >"$ai_memory_log"
  : >"$token_log"
  if (
    cd "$token_home/projects/agents"
    HOME="$token_home" \
      PATH="$token_stub:/usr/bin:/bin" \
      OPENCODE_SERVER_ENABLED=true \
      AI_MEMORY_AUTH_TOKEN="operator-override" \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      OPENCODE_TEST_RAW_LOG="$raw_log" \
      OPENCODE_TEST_TOKEN_LOG="$token_log" \
      bash --noprofile --norc -c \
        'source "$HOME/.bash_aliases"; opencode'
  ); then
    require_file_content "$token_log" "operator-override"
  else
    not_ok "the wrapper failed with an explicit token"
  fi

  require_contains "$aliases" 'export PATH="$HOME/.opencode/bin:$HOME/.local/bin:$PATH"'
  rtk_path_home="$fixture_root/rtk-path-home"
  rtk_conflict_bin="$fixture_root/rtk-conflict-bin"
  mkdir -p "$rtk_path_home/.opencode/bin" "$rtk_path_home/.local/bin" "$rtk_conflict_bin"
  printf '%s\n' '#!/bin/sh' 'exit 8' >"$rtk_path_home/.local/bin/rtk"
  printf '%s\n' '#!/bin/sh' 'exit 9' >"$rtk_conflict_bin/rtk"
  chmod +x "$rtk_path_home/.local/bin/rtk" "$rtk_conflict_bin/rtk"
  if (
    HOME="$rtk_path_home"
    PATH="$rtk_conflict_bin:/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/shell/opencode.bash"
    [[ "$(command -v rtk)" == "$HOME/.local/bin/rtk" ]]
  ); then
    ok "managed OpenCode launches find the newly installed RTK before older PATH entries"
  else
    not_ok "managed OpenCode launches can select an older RTK before the installed CLI"
  fi
  cp "$aliases" "$first_aliases"

  if (
    HOME="$fixture_home"
    source "$REPO_DIR/apply.sh"
    merge_opencode_shell_override
  ) >/dev/null 2>&1; then
    ok "OpenCode Bash override fixture applies a second time"
  else
    not_ok "OpenCode Bash override second apply failed"
  fi
  require_same_file "$first_aliases" "$aliases"

  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${1:-}" == "run" ]]; then' \
    '  case "${2:-}" in' \
    '    claude|codex|opencode|opencode2|pi|crush|omp|kimi|command-code|kiro|grok|antigravity) ;;' \
    '    *) printf '\''error: invalid value %s for [HARNESS]\n'\'' "${2:-}" >&2; exit 2 ;;' \
    '  esac' \
    'fi' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_AI_MEMORY_LOG"' \
    'exit "${OPENCODE_TEST_EXIT_STATUS:-0}"' >"$stub_bin/ai-memory"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
     'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_RAW_LOG"' >"$fixture_home/.opencode/bin/opencode"
  chmod +x "$stub_bin/ai-memory" "$fixture_home/.opencode/bin/opencode"

  # On any host the TUI uses a private server instead of the shared daemon.
  # The shared daemon has no AI_MEMORY_RUN_ID, so attaching to it with
  # --server breaks handoff delivery. --standalone avoids the port conflict
  # and keeps the managed context in the TUI process.
  : >"$ai_memory_log"
  server_host="$fixture_root/server-host"
  server_stub="$fixture_root/server-bin"
  mkdir -p "$server_host/projects/agents" "$server_host/.config/ai-memory" \
    "$server_host/.opencode/bin" "$server_stub"
  printf '%s\n' 'OPENCODE_SERVER_ENABLED=true' >"$server_host/.config/ai-memory/env"
  # --new returns 2 before it calls ai-memory unless the directory is a Git
  # work tree, so the fixture needs a real repository to reach the argument.
  (
    cd "$server_host/projects/agents"
    git init --quiet
    printf '%s\n' fixture >tracked.txt
    git -c user.email=fixture@example.test -c user.name=fixture add tracked.txt
    git -c user.email=fixture@example.test -c user.name=fixture \
      commit --quiet -m initial
  ) >/dev/null 2>&1
  # A private stub tree, because $stub_bin belongs to the previous fixture home
  # and this one has its own HOME.
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_AI_MEMORY_LOG"' >"$server_stub/ai-memory"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_RAW_LOG"' >"$server_host/.opencode/bin/opencode"
  chmod +x "$server_stub/ai-memory" "$server_host/.opencode/bin/opencode"
  cp "$aliases" "$server_host/.bash_aliases"
  if (
    cd "$server_host/projects/agents"
    HOME="$server_host" \
      PATH="$server_stub:/usr/bin:/bin" \
      OPENCODE_SERVER_ENABLED=true \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      OPENCODE_TEST_RAW_LOG="$raw_log" \
      bash --noprofile --norc -c \
        'source "$HOME/.bash_aliases"; opencode'
  ); then
    printf '%s\n' run opencode2 --executable "$server_host/.opencode/bin/opencode" \
      --standalone >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "a server host did not pass --standalone to ai-memory run"
  fi

  : >"$ai_memory_log"
  if (
    cd "$server_host/projects/agents"
    HOME="$server_host" \
      PATH="$server_stub:/usr/bin:/bin" \
      OPENCODE_SERVER_ENABLED=true \
      OPENCODE_SERVER_PORT=5000 \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      OPENCODE_TEST_RAW_LOG="$raw_log" \
      bash --noprofile --norc -c \
        'source "$HOME/.bash_aliases"; opencode --new'
  ) >/dev/null 2>&1; then
    printf '%s\n' run opencode2 --executable "$server_host/.opencode/bin/opencode" \
      --standalone >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "a server host did not pass --standalone for --new"
  fi

  : >"$ai_memory_log"
  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode -c "two words"'; then
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone -c 'two words' >"$expected"
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
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone session list >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode session utility forwarding failed"
  fi

  set +e
  HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    OPENCODE_TEST_RAW_LOG="$raw_log" \
    OPENCODE_TEST_EXIT_STATUS=7 \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode -c "fixture task"'
  managed_rc=$?
  set -e
  if [[ "$managed_rc" -eq 7 ]]; then
    ok "managed OpenCode launch preserves child exit status"
  else
    not_ok "managed OpenCode launch returned $managed_rc instead of 7"
  fi
  printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone -c 'fixture task' >"$expected"
  require_same_file "$expected" "$ai_memory_log"

  if HOME="$fixture_home" PATH="$stub_bin:/usr/bin:/bin" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; ! bash --noprofile --norc -c "declare -F opencode >/dev/null"'; then
    ok "managed OpenCode function remains unexported"
  else
    not_ok "managed OpenCode function was exported"
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

  # The wrapper has one behavior: a local, always-managed ai-memory workstream.
  # A client machine cannot ask for a server-side session through the shell, so
  # no OPENCODE_SERVER_URL value may change what the wrapper does.
  mkdir -p "$fixture_home/.config/opencode" "$fixture_home/projects/agents"
  printf '%s\n' \
    'OPENCODE_SERVER_URL=https://server.example.test' \
    "OPENCODE_CLIENT_HOME=$fixture_home" \
    'OPENCODE_SERVER_HOME=/Users/guisaliba' >"$fixture_home/.config/opencode/server.env"
  chmod 600 "$fixture_home/.config/opencode/server.env"
  : >"$ai_memory_log"
  if (
    cd "$fixture_home/projects/agents"
    HOME="$fixture_home" \
      PATH="$stub_bin:/usr/bin:/bin" \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      bash --noprofile --norc -c 'source "$HOME/.bash_aliases"; opencode'
  ); then
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode launch ignored a configured server URL"
  fi
  : >"$ai_memory_log"
  if HOME="$fixture_home" \
    PATH="$stub_bin:/usr/bin:/bin" \
    OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
    bash --noprofile --norc -c \
      'source "$HOME/.bash_aliases"; opencode "$HOME/projects/agents"'; then
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" \
      --standalone "$fixture_home/projects/agents" >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode explicit-directory forwarding failed"
  fi
  : >"$ai_memory_log"
  if (
    cd "$fixture_home/projects/agents"
    HOME="$fixture_home" \
      PATH="$stub_bin:/usr/bin:/bin" \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      bash --noprofile --norc -c 'source "$HOME/.bash_aliases"; opencode -c'
  ); then
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone -c >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode continue-flag forwarding failed"
  fi
  : >"$ai_memory_log"
  if (
    cd "$fixture_home/projects/agents"
    HOME="$fixture_home" \
      PATH="$stub_bin:/usr/bin:/bin" \
      OPENCODE_TEST_AI_MEMORY_LOG="$ai_memory_log" \
      bash --noprofile --norc -c 'source "$HOME/.bash_aliases"; opencode --fresh'
  ); then
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone --fresh >"$expected"
    require_same_file "$expected" "$ai_memory_log"
  else
    not_ok "managed OpenCode fresh-flag forwarding failed"
  fi
  require_text_count "$aliases" "OPENCODE_SERVER_URL" "0"
  require_text_count "$aliases" "OPENCODE_CLIENT_HOME" "0"
  require_text_count "$aliases" "OPENCODE_SERVER_HOME" "0"
  require_text_count "$aliases" '"$HOME/.opencode/bin/opencode" --server' "0"
  require_text_count "$aliases" "--server http" "0"
  require_text_count "$aliases" "OPENCODE_SERVER_PORT" "0"

  # opencode --new gives the session its own checkout, so concurrent sessions in
  # one repository never share a working tree. Each checkout is its own
  # workstream, and all of them resolve to the same ai-memory project.
  new_repo="$fixture_home/projects/widget"
  new_log="$fixture_root/new-ai-memory.log"
  new_out="$fixture_root/new-out.log"
  mkdir -p "$new_repo"
  printf '%s\n' 'stub' >"$new_repo/tracked.txt"
  if (
    cd "$new_repo"
    git init --quiet >/dev/null 2>&1
    git -c user.email=fixture@example.test -c user.name=fixture \
      add tracked.txt >/dev/null 2>&1
    git -c user.email=fixture@example.test -c user.name=fixture \
      commit --quiet -m initial >/dev/null 2>&1
  ); then
    ok "opencode --new fixture repository is initialized"
  else
    not_ok "opencode --new fixture repository could not be initialized"
  fi
  if (
    cd "$new_repo"
    HOME="$fixture_home" \
      PATH="$stub_bin:/usr/bin:/bin" \
      OPENCODE_TEST_AI_MEMORY_LOG="$new_log" \
      bash --noprofile --norc -c 'source "$HOME/.bash_aliases"; opencode --new'
  ) >"$new_out" 2>&1; then
    new_worktree="$(sed -n 's/^worktree: //p' "$new_out" | head -1)"
    if [[ -n "$new_worktree" && -d "$new_worktree" ]] && \
      git -C "$new_worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      ok "opencode --new creates a usable Git worktree"
    else
      not_ok "opencode --new did not report a usable Git worktree"
    fi
    printf '%s\n' run opencode2 --executable "$fixture_home/.opencode/bin/opencode" --standalone >"$expected"
    require_same_file "$expected" "$new_log"
    if grep -q -- "--new" "$new_log"; then
      not_ok "opencode --new leaked its own flag to ai-memory"
    else
      ok "opencode --new consumes its own flag before calling ai-memory"
    fi
    if git -C "$new_repo" worktree list | grep -qF "$new_worktree"; then
      ok "opencode --new registers the worktree with the repository"
    else
      not_ok "opencode --new left the worktree unregistered"
    fi
  else
    not_ok "opencode --new failed"
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
    source "$REPO_DIR/apply.sh"
    merge_opencode_shell_override
  ) >"$malformed_log" 2>&1; then
    not_ok "malformed OpenCode Bash wrapper markers were accepted"
  else
    ok "malformed OpenCode Bash wrapper markers fail safely"
  fi
  require_same_file "$malformed_before" "$malformed_aliases"
  require_contains "$malformed_log" "Expected one balanced OpenCode wrapper block"

  temp_source_home="$fixture_root/temp-source-home"
  temp_source="$fixture_root/temp-source"
  temp_source_aliases="$temp_source_home/.bash_aliases"
  temp_source_first="$fixture_root/temp-source-first"
  mkdir -p "$temp_source_home"
  printf '%s\n' \
    'alias source-only-alias=printf-source-only' \
    "$OPENCODE_SHELL_BLOCK_START" \
    'opencode() { command ai-memory run opencode "$@"; }' \
    'opencode-raw() { command opencode "$@"; }' \
    "$OPENCODE_SHELL_BLOCK_END" \
    'alias source-trailing-alias=printf-source-trailing' >"$temp_source"
  if (
    HOME="$temp_source_home"
    BASH_ALIASES_SOURCE="$temp_source"
    source "$REPO_DIR/apply.sh"
    merge_opencode_shell_override
  ) >/dev/null 2>&1; then
    ok "OpenCode Bash override fixture uses a temporary BASH_ALIASES_SOURCE"
  else
    not_ok "OpenCode Bash override fixture with a temporary source failed"
  fi
  require_text_count "$temp_source_aliases" "$OPENCODE_SHELL_BLOCK_START" "1"
  require_text_count "$temp_source_aliases" "$OPENCODE_SHELL_BLOCK_END" "1"
  require_contains "$temp_source_aliases" 'opencode() { command ai-memory run opencode "$@"; }'
  require_contains "$temp_source_aliases" 'opencode-raw() {'
  require_text_count "$temp_source_aliases" "alias source-only-alias" "0"
  require_text_count "$temp_source_aliases" "alias source-trailing-alias" "0"
  cp "$temp_source_aliases" "$temp_source_first"
  if (
    HOME="$temp_source_home"
    BASH_ALIASES_SOURCE="$temp_source"
    source "$REPO_DIR/apply.sh"
    merge_opencode_shell_override
  ) >/dev/null 2>&1; then
    ok "OpenCode Bash override fixture with a temporary source applies a second time"
  else
    not_ok "OpenCode Bash override fixture with a temporary source second apply failed"
  fi
  require_same_file "$temp_source_first" "$temp_source_aliases"

  rm -rf -- "$fixture_root"
}

test_optional_ai_jail() {
  local fixture_root stub_bin
  fixture_root="$(mktemp -d)"
  stub_bin="$fixture_root/bin"
  mkdir -p "$stub_bin"

  if (
    PATH="$stub_bin:/usr/bin:/bin"
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
    uname() { [[ "$1" == -s ]] && printf '%s\n' Linux; }
    install_ai_memory
  ) >"$wrapper_log" 2>&1; then
    not_ok "Docker ai-memory wrapper was accepted as a native binary"
  else
    ok "Docker ai-memory wrapper is rejected before setup"
  fi
  require_contains "$wrapper_log" "ai-memory must be a native Linux executable"

  printf '\177ELFfixture' >"$stub_bin/ai-memory"
  chmod +x "$stub_bin/ai-memory"
  if (
    PATH="$stub_bin:/usr/bin:/bin"
    source "$REPO_DIR/apply.sh"
    uname() { [[ "$1" == -s ]] && printf '%s\n' Linux; }
    verify_native_ai_memory
  ) >/dev/null 2>&1; then
    ok "native Linux executable satisfies the ai-memory binary check"
  else
    not_ok "native Linux executable was rejected"
  fi

  printf '\317\372\355\376fixture' >"$stub_bin/ai-memory"
  chmod +x "$stub_bin/ai-memory"
  printf '%s\n' '#!/bin/bash' 'printf '\''Darwin\n'\''' >"$stub_bin/uname"
  chmod +x "$stub_bin/uname"
  if (
    PATH="$stub_bin:/usr/bin:/bin"
    source "$REPO_DIR/apply.sh"
    verify_native_ai_memory
  ) >/dev/null 2>&1; then
    ok "native macOS executable satisfies the ai-memory binary check"
  else
    not_ok "native macOS executable was rejected"
  fi

  rm -rf -- "$fixture_root"
}

test_macos_ai_memory_installation() {
  local fixture_root fixture_home fixture_source fixture_archive stub_bin install_log expected_url
  local runtime binary
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_source="$fixture_root/release"
  fixture_archive="$fixture_root/ai-memory-macos-aarch64.tar.gz"
  stub_bin="$fixture_root/bin"
  install_log="$fixture_root/download.log"
  runtime="$fixture_home/.local/opt/ai-memory/$AI_MEMORY_RELEASE_VERSION_EXPECTED"
  binary="$fixture_home/.local/bin/ai-memory"
  expected_url="https://github.com/akitaonrails/ai-memory/releases/download/v$AI_MEMORY_RELEASE_VERSION_EXPECTED/ai-memory-macos-aarch64.tar.gz"
  mkdir -p "$fixture_source/hooks/opencode" "$fixture_source/packaging/launchd" "$stub_bin"
  printf '%s\n' '#!/bin/bash' "printf 'ai-memory $AI_MEMORY_RELEASE_VERSION_EXPECTED\\n'" >"$fixture_source/ai-memory"
  chmod +x "$fixture_source/ai-memory"
  printf '%s\n' fixture >"$fixture_source/hooks/opencode/session-start.sh"
  printf '%s\n' fixture >"$fixture_source/packaging/launchd/com.github.akitaonrails.ai-memory.plist"
  tar -czf "$fixture_archive" -C "$fixture_source" .

  printf '%s\n' \
    '#!/bin/bash' \
    'case "${1:-}" in' \
    '  -s) printf '\''Darwin\n'\'' ;;' \
    '  -m) printf '\''arm64\n'\'' ;;' \
    '  *) exit 2 ;;' \
    'esac' >"$stub_bin/uname"
  printf '%s\n' \
    '#!/bin/bash' \
    'output=' \
    'printf '\''%s\n'\'' "$*" >>"$AI_MEMORY_TEST_DOWNLOAD_LOG"' \
    'while [[ $# -gt 0 ]]; do' \
    '  if [[ "$1" == --output ]]; then shift; output="$1"; fi' \
    '  shift' \
    'done' \
    'cp "$AI_MEMORY_TEST_ARCHIVE" "$output"' >"$stub_bin/curl"
  printf '%s\n' \
    '#!/bin/bash' \
    'printf '\''%s  %s\n'\'' "$AI_MEMORY_TEST_SHA256" "${3:-}"' >"$stub_bin/shasum"
  chmod +x "$stub_bin/uname" "$stub_bin/curl" "$stub_bin/shasum"
  for command_name in bash chmod cp dirname gzip ln mkdir mktemp mv python3 readlink rm tar; do
    ln -s "$(command -v "$command_name")" "$stub_bin/$command_name"
  done

  if (
    HOME="$fixture_home"
    PATH="$fixture_home/.local/bin:$stub_bin"
    AI_MEMORY_TEST_ARCHIVE="$fixture_archive"
    AI_MEMORY_TEST_DOWNLOAD_LOG="$install_log"
    AI_MEMORY_TEST_SHA256="$AI_MEMORY_MACOS_AARCH64_SHA256_EXPECTED"
    export HOME PATH AI_MEMORY_TEST_ARCHIVE AI_MEMORY_TEST_DOWNLOAD_LOG AI_MEMORY_TEST_SHA256
    source "$REPO_DIR/apply.sh"
    verify_native_ai_memory() { :; }
    install_ai_memory
    install_ai_memory
  ) >/dev/null 2>&1; then
    ok "pinned macOS ai-memory release fixture installs"
  else
    not_ok "pinned macOS ai-memory release fixture failed"
  fi
  require_executable "$runtime/ai-memory"
  require_dir "$runtime/hooks/opencode"
  if [[ -L "$binary" && "$(readlink "$binary")" == "$runtime/ai-memory" ]]; then
    ok "macOS ai-memory command links to the stable release bundle"
  else
    not_ok "macOS ai-memory command does not link to the stable release bundle"
  fi
  require_text_count "$install_log" "$expected_url" "1"

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
    '# Managed by guisaliba/agents apply.sh.' \
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
    source "$REPO_DIR/apply.sh"
    uname() { [[ "$1" == -s ]] && printf '%s\n' Linux; }
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
    source "$REPO_DIR/apply.sh"
    uname() { [[ "$1" == -s ]] && printf '%s\n' Linux; }
    install_ai_memory_user_service
  ) >/dev/null 2>&1; then
    ok "ai-memory user service installation applies a second time"
  else
    not_ok "second ai-memory user service installation failed"
  fi
  require_same_file "$first_service" "$service_file"

  rm -rf -- "$fixture_root"
}

test_macos_ai_memory_launch_daemon() {
  local fixture_root fixture_home stub_bin executable daemon_source daemon_file install_log
  local old_agent launch_log expected_log username group uid
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  executable="$stub_bin/ai-memory"
  daemon_source="$fixture_home/.config/ai-memory/com.github.akitaonrails.ai-memory.plist"
  daemon_file="$fixture_root/Library/LaunchDaemons/com.github.akitaonrails.ai-memory.plist"
  install_log="$fixture_root/install-required.log"
  old_agent="$fixture_home/Library/LaunchAgents/com.github.akitaonrails.ai-memory.plist"
  launch_log="$fixture_root/launchctl.log"
  expected_log="$fixture_root/expected-launchctl.log"
  username="$(id -un)"
  group="$(id -gn)"
  uid="$(id -u)"
  mkdir -p "$stub_bin"
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$executable"
  printf '%s\n' '#!/bin/bash' 'printf '\''Darwin\n'\''' >"$stub_bin/uname"
  chmod +x "$executable"
  chmod +x "$stub_bin/uname"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    export HOME PATH AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE
    source "$REPO_DIR/apply.sh"
    install_ai_memory_launch_daemon
  ) >/dev/null 2>&1; then
    ok "macOS ai-memory LaunchDaemon source is generated"
  else
    not_ok "macOS ai-memory LaunchDaemon source generation failed"
  fi
  require_file "$daemon_source"
  require_file_mode "$daemon_source" "600"
  require_file_mode "$fixture_home/Library/Logs/ai-memory" "700"
  require_file_mode "$fixture_home/Library/Logs/ai-memory/stdout.log" "600"
  require_file_mode "$fixture_home/Library/Logs/ai-memory/stderr.log" "600"
  if python3 - "$daemon_source" "$executable" "$fixture_home" "$username" "$group" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
executable = sys.argv[2]
home = sys.argv[3]
username = sys.argv[4]
group = sys.argv[5]
with path.open("rb") as stream:
    config = plistlib.load(stream)

assert config == {
    "Label": "com.github.akitaonrails.ai-memory",
    "UserName": username,
    "GroupName": group,
    "ProgramArguments": [
        "/bin/bash",
        "-c",
        'set -a; [[ ! -f "$1" ]] || source "$1"; shift; exec "$@"',
        "ai-memory-service",
        f"{home}/.config/ai-memory/env",
        executable,
        "--data-dir",
        f"{home}/.local/share/ai-memory",
        "--config",
        f"{home}/.config/ai-memory/config.toml",
        "serve",
        "--transport",
        "http",
        "--enable-web",
    ],
    "RunAtLoad": True,
    "KeepAlive": True,
    "WorkingDirectory": home,
    "EnvironmentVariables": {
        "HOME": home,
        "USER": username,
        "LOGNAME": username,
    },
    "StandardOutPath": f"{home}/Library/Logs/ai-memory/stdout.log",
    "StandardErrorPath": f"{home}/Library/Logs/ai-memory/stderr.log",
}
PY
  then
    ok "macOS ai-memory LaunchDaemon has the required runtime contract"
  else
    not_ok "macOS ai-memory LaunchDaemon has incorrect content"
  fi

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    AI_MEMORY_LAUNCH_DAEMON_FILE="$daemon_file"
    export HOME PATH AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE AI_MEMORY_LAUNCH_DAEMON_FILE
    source "$REPO_DIR/apply.sh"
    start_ai_memory_service
  ) >"$install_log" 2>&1; then
    not_ok "missing macOS ai-memory LaunchDaemon did not require privileged installation"
  else
    ok "missing macOS ai-memory LaunchDaemon requires privileged installation"
  fi
  require_contains "$install_log" "sudo install -o root -g wheel -m 0644"
  require_contains "$install_log" "sudo launchctl bootstrap system"
  require_contains "$install_log" "sudo launchctl kickstart -k"

  mkdir -p "$(dirname "$daemon_file")" "$(dirname "$old_agent")"
  cp "$daemon_source" "$daemon_file"
  printf '%s\n' obsolete >"$old_agent"
  printf '%s\n' '#!/bin/bash' 'printf '\''%s\n'\'' "$*" >>"$AI_MEMORY_TEST_LAUNCHCTL_LOG"' >"$stub_bin/launchctl"
  printf '%s\n' '#!/bin/bash' 'printf '\''root:wheel:644\n'\''' >"$stub_bin/stat"
  chmod +x "$stub_bin/launchctl" "$stub_bin/stat"
  printf '%s\n' \
    "print system/com.github.akitaonrails.ai-memory" \
    "bootout gui/$uid/com.github.akitaonrails.ai-memory" >"$expected_log"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    AI_MEMORY_TEST_LAUNCHCTL_LOG="$launch_log"
    AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    AI_MEMORY_LAUNCH_DAEMON_FILE="$daemon_file"
    AI_MEMORY_LAUNCH_AGENT_FILE="$old_agent"
    export HOME PATH AI_MEMORY_TEST_LAUNCHCTL_LOG AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE AI_MEMORY_LAUNCH_DAEMON_FILE AI_MEMORY_LAUNCH_AGENT_FILE
    source "$REPO_DIR/apply.sh"
    start_ai_memory_service
  ) >/dev/null 2>&1; then
    ok "active macOS ai-memory LaunchDaemon satisfies setup"
  else
    not_ok "active macOS ai-memory LaunchDaemon was rejected"
  fi
  require_same_file "$expected_log" "$launch_log"
  if [[ ! -e "$old_agent" ]]; then
    ok "obsolete macOS ai-memory LaunchAgent is removed after daemon activation"
  else
    not_ok "obsolete macOS ai-memory LaunchAgent remains after daemon activation"
  fi

  rm -rf -- "$fixture_root"
}

test_macos_bash_profile() {
  local fixture_root fixture_home stub_bin profile first_profile
  local linux_home linux_profile linux_first
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  profile="$fixture_home/.bash_profile"
  first_profile="$fixture_root/first-profile"
  mkdir -p "$fixture_home" "$stub_bin"
  printf '%s\n' 'export PRESERVE_ME=yes' >"$profile"
  printf '%s\n' '#!/bin/bash' 'printf '\''Darwin\n'\''' >"$stub_bin/uname"
  chmod +x "$stub_bin/uname"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    configure_bash_login_env
    configure_bash_login_env
  ) >/dev/null 2>&1; then
    ok "macOS Bash profile setup applies twice"
  else
    not_ok "macOS Bash profile setup failed"
  fi
  require_contains "$profile" "export PRESERVE_ME=yes"
  require_text_count "$profile" "# >>> guisaliba/agents Bash aliases >>>" "1"
  require_text_count "$profile" "# <<< guisaliba/agents Bash aliases <<<" "1"
  require_contains "$profile" 'source "$HOME/.bash_aliases"'
  require_contains "$profile" 'source "$HOME/.profile"'
  cp "$profile" "$first_profile"

  # Every platform needs the env file loaded, not just macOS. On a client host
  # the ai-memory CLI reads AI_MEMORY_SERVER_URL from the environment only, so
  # a block written solely on macOS leaves a Linux client unable to reach the
  # server at all.
  linux_home="$fixture_root/linux-home"
  linux_profile="$linux_home/.bash_profile"
  linux_first="$fixture_root/linux-first-profile"
  mkdir -p "$linux_home"
  printf '%s\n' 'export PRESERVE_LINUX=yes' >"$linux_profile"
  if (
    HOME="$linux_home"
    PATH="/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    configure_bash_login_env
    configure_bash_login_env
  ) >/dev/null 2>&1; then
    ok "Linux Bash profile setup applies twice"
  else
    not_ok "Linux Bash profile setup failed"
  fi
  require_contains "$linux_profile" "export PRESERVE_LINUX=yes"
  require_text_count "$linux_profile" "# >>> guisaliba/agents Bash aliases >>>" "1"
  require_contains "$linux_profile" 'source "$HOME/.bash_aliases"'
  require_contains "$linux_profile" 'source "$HOME/.profile"'
  require_contains "$linux_profile" 'source "$HOME/.config/ai-memory/env"'
  require_contains "$linux_profile" 'source "$HOME/.config/opencode/server.env"'
  require_contains "$linux_profile" 'AI_MEMORY_AUTH_TOKEN="$(tr -d'
  require_contains "$linux_profile" '$HOME/.config/ai-memory/client-token'
  cp "$linux_profile" "$linux_first"
  if (
    HOME="$linux_home"
    PATH="/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    configure_bash_login_env
  ) >/dev/null 2>&1; then
    ok "Linux Bash profile setup is idempotent"
  else
    not_ok "Linux Bash profile second apply failed"
  fi
  require_same_file "$linux_first" "$linux_profile"

  rm -rf -- "$fixture_root"
}

test_opencode_launch_daemon() {
  local fixture_root fixture_home binary env_file plist first_plist
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  binary="$fixture_home/.opencode/bin/opencode"
  env_file="$fixture_home/.config/opencode/server.env"
  plist="$fixture_home/.config/opencode/com.opencode.server.plist"
  first_plist="$fixture_root/first.plist"
  mkdir -p "$(dirname "$binary")" "$(dirname "$env_file")"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$binary"
  chmod +x "$binary"
  printf '%s\n' 'OPENCODE_SERVER_PASSWORD=fixture-secret' >"$env_file"
  chmod 600 "$env_file"

  if (
    HOME="$fixture_home"
    OPENCODE_BINARY="$binary"
    OPENCODE_SERVER_ENABLED=true
    OPENCODE_SERVER_ENV_FILE="$env_file"
    OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE="$plist"
    OPENCODE_SERVER_LOG_DIR="$fixture_home/Library/Logs/opencode"
    export HOME OPENCODE_BINARY OPENCODE_SERVER_ENABLED OPENCODE_SERVER_ENV_FILE OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE OPENCODE_SERVER_LOG_DIR
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    install_opencode_launch_daemon_source
    install_opencode_launch_daemon_source
  ) >/dev/null 2>&1; then
    ok "OpenCode LaunchDaemon source fixture applies twice"
  else
    not_ok "OpenCode LaunchDaemon source fixture failed"
  fi
  require_file "$plist"
  require_file_mode "$plist" "600"
  if python3 - "$plist" "$binary" "$env_file" <<'PY'
import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open("rb") as handle:
    data = plistlib.load(handle)
args = data["ProgramArguments"]
assert data["Label"] == "com.opencode.server"
assert data["UserName"]
assert data["GroupName"]
assert data["RunAtLoad"] is True
assert data["KeepAlive"] == {"SuccessfulExit": False}
assert args[4] == sys.argv[3]
assert args[5] == sys.argv[2]
assert args[6:] == ["serve", "--hostname", "127.0.0.1", "--port", "4096"]
assert "OPENCODE_SERVER_PASSWORD" not in repr(data)
PY
  then
    ok "OpenCode LaunchDaemon has the required headless service contract"
  else
    not_ok "OpenCode LaunchDaemon contract is invalid"
  fi
  cp "$plist" "$first_plist"
  require_same_file "$first_plist" "$plist"
  rm -rf -- "$fixture_root"
}

# Repo structure checks
printf '\n--- Repo Structure ---\n'

require_file "$REPO_DIR/AGENTS.md"
require_file "$REPO_DIR/README.md"
require_file "$REPO_DIR/LICENSE"
require_file "$REPO_DIR/apply.sh"
require_file "$REPO_DIR/test.sh"
require_file "$REPO_DIR/opencode/README.md"
shopt -s nullglob
tracked_theme_files=("$REPO_DIR"/opencode/themes/*.json)
shopt -u nullglob
if [[ ${#tracked_theme_files[@]} -gt 0 ]]; then
  ok "tracked OpenCode themes are present"
else
  not_ok "no tracked OpenCode themes are present"
fi
for theme_file in "${tracked_theme_files[@]}"; do
  require_json "$theme_file"
done
require_contains "$REPO_DIR/apply.sh" "merge_opencode_cli_json"
require_contains "$REPO_DIR/apply.sh" "--agent opencode2"
require_file "$REPO_DIR/plugins/rtk/rtk.ts"
require_file "$REPO_DIR/plugins/rtk/README.md"
require_file "$REPO_DIR/plugins/rtk/LICENSE"
require_file "$REPO_DIR/plugins/rtk/rtk.test.ts"
require_file "$REPO_DIR/plugins/rtk/rtk-resolver.test.ts"
require_file "$REPO_DIR/plugins/rtk/smoke-test.py"
require_file "$REPO_DIR/plugins/rtk/verification.md"
require_contains "$REPO_DIR/apply.sh" 'RTK_VERSION="${RTK_VERSION:-v0.50.0}"'
require_contains "$REPO_DIR/apply.sh" "install_rtk_plugin"
require_text_count "$REPO_DIR/apply.sh" "rtk init -g --opencode" "0"
require_file "$REPO_DIR/skills/README.md"
require_file "$REPO_DIR/skills/daily-tasks/SKILL.md"
require_executable "$REPO_DIR/skills/daily-tasks/scripts/journal-task-sync"
require_file "$REPO_DIR/lib/agent_stack.py"
require_file "$REPO_DIR/skills.tsv"
require_file "$REPO_DIR/shell/opencode.bash"
require_executable "$REPO_DIR/apply.sh"
require_executable "$REPO_DIR/test.sh"
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
require_skill_manifest_entry "local" "daily-tasks" "skills/daily-tasks" "yes"
if [[ "$manifest_valid" == true ]]; then
  while IFS=$'\t' read -r provider name source_ref require_skill_file; do
    case "$provider" in
      local)
        require_dir "$REPO_DIR/$source_ref"
        ;;
      upstream)
        if [[ ! -e "$REPO_DIR/skills/$name" ]]; then
          ok "$name is not locally vendored"
        else
          not_ok "$name must be installed from upstream, not locally vendored"
        fi
        ;;
    esac
  done <<<"$manifest_rows"
fi
require_text_count "$REPO_DIR/shell/opencode.bash" "$OPENCODE_SHELL_BLOCK_START" "1"
require_text_count "$REPO_DIR/shell/opencode.bash" "$OPENCODE_SHELL_BLOCK_END" "1"

# OpenCode merge fixture checks
printf '\n--- OpenCode Merge Fixtures ---\n'

test_opencode_json_merge
test_opencode_cli_json_merge

# ai-memory secret-file fixture checks
printf '\n--- ai-memory File Fixtures ---\n'

test_ai_memory_service_staleness
test_ai_memory_token_delivery
test_ai_memory_env_file

# Shared helper fixture checks
printf '\n--- Shared Helper Fixtures ---\n'

test_agent_stack_helpers
test_macos_platform_prerequisites
test_apply_scope

# RTK plugin fixture checks. The resolver test runs in its own Bun process so
# its node:fs mock cannot affect the real-child-process tests.
printf '\n--- RTK Plugin Fixtures ---\n'
test_rtk_plugin_installation
test_rtk_unsafe_target_handling
test_rtk_duplicate_local_plugin_handling
test_rtk_cli_compatibility_ignores_user_policy
test_rtk_cli_installation
bun test "$REPO_DIR/plugins/rtk/rtk.test.ts" || not_ok "RTK rewrite behavior tests failed"
bun test "$REPO_DIR/plugins/rtk/rtk-resolver.test.ts" || not_ok "RTK resolver tests failed"

# Manifest installation fixture checks
printf '\n--- Skill Installation Fixtures ---\n'

test_required_skill_installation

# Daily task sync fixture checks
printf '\n--- Daily Task Sync Fixtures ---\n'

test_daily_task_sync

# Bash command override fixture checks
printf '\n--- OpenCode Bash Override Fixtures ---\n'

test_opencode_shell_override

# Optional ai-jail fixture checks
printf '\n--- Optional ai-jail Fixtures ---\n'

test_optional_ai_jail

# Native ai-memory fixture checks
printf '\n--- Native ai-memory Fixtures ---\n'

test_native_ai_memory_requirement
test_macos_ai_memory_installation
test_ai_memory_user_service_installation
test_macos_ai_memory_launch_daemon
test_macos_bash_profile
test_opencode_launch_daemon

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
require_command bun
require_executable "$HOME/.opencode/bin/opencode"
require_command ai-memory
require_command rtk
require_command plannotator
if [[ -f "$HOME/.config/opencode/plugins/rtk.ts" && ! -L "$HOME/.config/opencode/plugins/rtk.ts" ]] && \
  cmp -s "$REPO_DIR/plugins/rtk/rtk.ts" "$HOME/.config/opencode/plugins/rtk.ts"; then
  ok "installed RTK V2 plugin matches the tracked payload"
else
  not_ok "installed RTK V2 plugin does not match the tracked payload"
fi

"$HOME/.opencode/bin/opencode" --help >/dev/null 2>&1 && ok "OpenCode V2 help runs" || not_ok "OpenCode V2 help failed"
ai-memory --help >/dev/null 2>&1 && ok "ai-memory help runs" || not_ok "ai-memory help failed"
plannotator --help >/dev/null 2>&1 && ok "plannotator help runs" || not_ok "plannotator help failed"

if (
  source "$REPO_DIR/apply.sh"
  require_minimum_version bun "$BUN_MIN_VERSION"
) >/dev/null 2>&1; then
  ok "bun is installed at version $BUN_MIN_VERSION or newer"
else
  not_ok "bun is missing, is older than $BUN_MIN_VERSION, or is unreadable"
fi

if (
  source "$REPO_DIR/apply.sh"
  require_minimum_version "$HOME/.opencode/bin/opencode" "$OPENCODE_MIN_VERSION"
) >/dev/null 2>&1; then
  ok "OpenCode V2 is installed at version $OPENCODE_MIN_VERSION or newer"
else
  not_ok "OpenCode V2 is missing, too old, or unreadable"
fi

if (
  source "$REPO_DIR/apply.sh"
  verify_native_ai_memory
) >/dev/null 2>&1; then
  ok "ai-memory is a native executable for this platform"
else
  not_ok "ai-memory is not a native executable for this platform or is unreadable"
fi

if (
  source "$REPO_DIR/apply.sh"
  require_minimum_version ai-memory "$AI_MEMORY_MIN_VERSION"
) >/dev/null 2>&1; then
  ok "ai-memory is installed at version $AI_MEMORY_MIN_VERSION or newer"
else
  not_ok "ai-memory is missing, is older than $AI_MEMORY_MIN_VERSION, or is unreadable"
fi

if command -v ai-jail >/dev/null 2>&1; then
  ai-jail --help >/dev/null 2>&1 && ok "optional ai-jail help runs" || not_ok "optional ai-jail help failed"
else
  ok "optional ai-jail command is not installed"
fi

rewritten="$(rtk rewrite "git status --short" 2>/dev/null || true)"
[[ "$rewritten" == "rtk git status --short" ]] && ok "rtk rewrite runs" || not_ok "rtk rewrite failed"

require_file "$HOME/.config/opencode/AGENTS.md"
require_contains "$HOME/.config/opencode/AGENTS.md" "ASD-STE100"
require_contains "$HOME/.config/opencode/AGENTS.md" "<!-- ai-memory:start -->"
require_contains "$HOME/.config/opencode/AGENTS.md" "<!-- ai-memory:end -->"
require_file "$HOME/.bash_aliases"
require_text_count "$HOME/.bash_aliases" "$OPENCODE_SHELL_BLOCK_START" "1"
require_text_count "$HOME/.bash_aliases" "$OPENCODE_SHELL_BLOCK_END" "1"
interactive_bash_flags="-ic"
if [[ "$(uname -s)" == Darwin ]]; then
  interactive_bash_flags="-lic"
fi
if bash "$interactive_bash_flags" 'declare -F opencode >/dev/null && declare -F opencode-raw >/dev/null' \
  </dev/null >/dev/null 2>&1; then
  ok "interactive Bash loads managed opencode and opencode-raw functions"
else
  not_ok "interactive Bash does not load the managed OpenCode functions"
fi
require_file "$GITHUB_MCP_TOKEN_FILE"
require_file_mode "$GITHUB_MCP_TOKEN_FILE" "600"
require_json "$HOME/.config/opencode/opencode.json"
require_json_value "$HOME/.config/opencode/opencode.json" "model" "openai/gpt-6-luna"
require_json_value "$HOME/.config/opencode/opencode.json" "default_agent" "build"
require_json_value "$HOME/.config/opencode/opencode.json" "agents.plan.model" "openai/gpt-6-luna"
selected_profile_log="$(mktemp)"
if selected_profile="$(
  source "$REPO_DIR/apply.sh"
  opencode_selected_subagent_profile 2>"$selected_profile_log"
)"; then
  ok "subagent profile selection is supported: $selected_profile"
  profile_spec="$(
    source "$REPO_DIR/apply.sh"
    opencode_subagent_profile_model "$selected_profile"
  )"
  require_json_value "$HOME/.config/opencode/opencode.json" "agents.general.model" "$profile_spec"
  require_json_value "$HOME/.config/opencode/opencode.json" "agents.explore.model" "$profile_spec"
else
  not_ok "subagent profile selection is unsupported or unreadable"
  sed 's/^/  /' "$selected_profile_log" >&2
fi
rm -f "$selected_profile_log"

if [[ -f "$HOME/.config/opencode/server.env" ]]; then
  set -a
  source "$HOME/.config/opencode/server.env"
  set +a
fi
if [[ -n "${OPENCODE_SERVER_URL:-}" ]]; then
  model_catalog="$(
    curl -fsS \
      -u "${OPENCODE_SERVER_USERNAME:-opencode}:$OPENCODE_SERVER_PASSWORD" \
      --get \
      --data-urlencode "location[directory]=$REPO_DIR" \
      "$OPENCODE_SERVER_URL/api/model" 2>/dev/null | \
      python3 -c '
import json
import sys
for model in json.load(sys.stdin).get("data", []):
    provider = model.get("providerID")
    model_id = model.get("id")
    if provider and model_id:
        print(f"{provider}/{model_id}")
' 2>/dev/null || true
  )"
else
  model_catalog="$("$HOME/.opencode/bin/opencode" models 2>/dev/null || true)"
fi
if [[ -n "$model_catalog" ]]; then
  model_catalog_lines=$'\n'"$model_catalog"$'\n'
  for profile_name in $(subagent_profile_names); do
    catalog_model="$(source "$REPO_DIR/apply.sh"; opencode_subagent_profile_model "$profile_name")"
    if [[ "$model_catalog_lines" == *$'\n'"$catalog_model"$'\n'* ]]; then
      ok "opencode model catalog contains $catalog_model"
    else
      not_ok "opencode model catalog does not contain $catalog_model for profile $profile_name"
    fi
  done
else
  if [[ -n "${OPENCODE_SERVER_URL:-}" ]]; then
    ok "remote model catalog is validated through the server agent API smoke test"
  else
    not_ok "opencode models returned no catalog"
  fi
fi
require_json_array_count "$HOME/.config/opencode/opencode.json" "instructions" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" "1"
require_json_array_count "$HOME/.config/opencode/opencode.json" "plugins" "$LEARN_PLUGIN_SPEC" "0"
require_json_array_count "$HOME/.config/opencode/opencode.json" "plugins" "$LEARN_LEGACY_PLUGIN_BASE" "0"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.servers.ai-memory.url" "$AI_MEMORY_EXPECTED_SERVER_URL/mcp"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.servers.ai-memory.disabled" "false"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.servers.github.type" "remote"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.servers.github.url" "https://api.githubcopilot.com/mcp/"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.servers.github.disabled" "false"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.servers.github.oauth" "false"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.servers.github.headers.Authorization" "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}"

require_contains "$HOME/.config/opencode/opencode.json" "@plannotator/opencode@latest"
require_file "$HOME/.config/opencode/cli.json"
require_json "$HOME/.config/opencode/cli.json"
require_json_value "$HOME/.config/opencode/cli.json" "theme.name" "$OPENCODE_TUI_THEME_EXPECTED"
[[ ! -e "$HOME/.config/opencode/tui.json" && ! -e "$HOME/.config/opencode/tui.jsonc" ]] && \
  ok "managed V1 TUI files are absent" || not_ok "managed V1 TUI files remain"
for theme_file in "${tracked_theme_files[@]}"; do
  require_same_file "$theme_file" "$HOME/.config/opencode/themes/${theme_file##*/}"
done
require_json_array_count "$HOME/.config/opencode/cli.json" "plugins" "$LEARN_PLUGIN_SPEC" "0"

require_dir "$LEARN_INSTALL_DIR"
require_file "$LEARN_INSTALL_DIR/package.json"
require_file "$LEARN_INSTALL_DIR/bun.lock"
require_file "$LEARN_INSTALL_DIR/src/server.ts"
require_file "$LEARN_INSTALL_DIR/src/tui.ts"
require_file "$LEARN_INSTALL_DIR/node_modules/@opencode-ai/plugin/package.json"
if [[ -d "$LEARN_INSTALL_DIR/.git" ]] && \
  [[ "$(git -C "$LEARN_INSTALL_DIR" rev-parse HEAD 2>/dev/null)" == "$(git -C "$LEARN_INSTALL_DIR" rev-parse "origin/$LEARN_BRANCH" 2>/dev/null)" ]]; then
  ok "managed Learn checkout matches origin/$LEARN_BRANCH"
else
  not_ok "managed Learn checkout does not match origin/$LEARN_BRANCH"
fi

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
  source "$REPO_DIR/apply.sh"
  [[ "$(uname -s)" != Darwin ]] || OPENCODE_SERVER_ENABLED=true
  verify_ai_memory_unauthenticated_loopback
) >/dev/null 2>&1; then
  ok "ai-memory authentication policy is consistent for this host role"
else
  not_ok "ai-memory authentication policy is inconsistent"
fi
require_file "$HOME/.config/opencode/plugins/ai-memory-opencode2.ts"
require_file_mode "$HOME/.config/opencode/plugins/ai-memory-opencode2.ts" "600"
require_contains "$HOME/.config/opencode/plugins/ai-memory-opencode2.ts" 'id: "ai-memory-opencode2"'
require_contains "$HOME/.config/opencode/plugins/ai-memory-opencode2.ts" "const SERVER = \"$AI_MEMORY_EXPECTED_SERVER_URL\""
require_file "$OPENCODE_SERVER_ENV_FILE"
require_file_mode "$OPENCODE_SERVER_ENV_FILE" "600"
case "$(uname -s)" in
  Linux)
    systemctl --user is-enabled --quiet ai-memory.service >/dev/null 2>&1 && \
      not_ok "local ai-memory user service remains enabled" || ok "local ai-memory user service is disabled"
    systemctl --user is-active --quiet ai-memory.service >/dev/null 2>&1 && \
      not_ok "local ai-memory user service remains active" || ok "local ai-memory user service is inactive"
    require_file "$HOME/.config/ai-memory/client-token"
    require_file_mode "$HOME/.config/ai-memory/client-token" "600"
    ;;
  Darwin)
    require_file "$OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE"
    require_file_mode "$OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE" "600"
    require_file "$OPENCODE_SERVER_LAUNCH_DAEMON_FILE"
    require_file_mode "$OPENCODE_SERVER_LAUNCH_DAEMON_FILE" "644"
    require_file "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE"
    require_file_mode "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE" "600"
    require_file "$AI_MEMORY_LAUNCH_DAEMON_FILE"
    require_file_mode "$AI_MEMORY_LAUNCH_DAEMON_FILE" "644"
    require_same_file "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE" "$AI_MEMORY_LAUNCH_DAEMON_FILE"
    require_file_mode "$HOME/Library/Logs/ai-memory" "700"
    require_file_mode "$HOME/Library/Logs/ai-memory/stdout.log" "600"
    require_file_mode "$HOME/Library/Logs/ai-memory/stderr.log" "600"
    if [[ "$(stat -f '%Su:%Sg' "$AI_MEMORY_LAUNCH_DAEMON_FILE" 2>/dev/null || true)" == "root:wheel" ]]; then
      ok "ai-memory LaunchDaemon is owned by root:wheel"
    else
      not_ok "ai-memory LaunchDaemon is not owned by root:wheel"
    fi
    if launchctl print "system/$AI_MEMORY_LAUNCH_AGENT_LABEL" >/dev/null 2>&1; then
      ok "ai-memory LaunchDaemon is active"
      require_ai_memory_status
    else
      not_ok "ai-memory LaunchDaemon is not active"
    fi
    if [[ ! -e "$AI_MEMORY_LAUNCH_AGENT_FILE" && ! -L "$AI_MEMORY_LAUNCH_AGENT_FILE" ]]; then
      ok "obsolete ai-memory LaunchAgent is absent"
    else
      not_ok "obsolete ai-memory LaunchAgent remains installed"
    fi
    ;;
esac

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
