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
  export PATH
fi

failures=0
GITHUB_MCP_TOKEN_FILE="$HOME/.config/opencode/secrets/github-mcp-pat"
GITHUB_MCP_EXPECTED_JSON='{"type":"remote","url":"https://api.githubcopilot.com/mcp/","enabled":true,"oauth":false,"headers":{"Authorization":"Bearer {file:~/.config/opencode/secrets/github-mcp-pat}","X-MCP-Toolsets":"context,repos,issues,pull_requests,actions"}}'
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
AI_MEMORY_INSTRUCTIONS_FILE="$HOME/.config/opencode/ai-memory.md"
AI_MEMORY_INSTRUCTIONS_REFERENCE="~/.config/opencode/ai-memory.md"
AI_MEMORY_USER_SERVICE_FILE="$HOME/.config/systemd/user/ai-memory.service"
AI_MEMORY_LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/com.github.akitaonrails.ai-memory.plist"
AI_MEMORY_LAUNCH_AGENT_LABEL="com.github.akitaonrails.ai-memory"
AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="$HOME/.config/ai-memory/com.github.akitaonrails.ai-memory.plist"
AI_MEMORY_LAUNCH_DAEMON_FILE="/Library/LaunchDaemons/com.github.akitaonrails.ai-memory.plist"
AI_MEMORY_MCP_EXPECTED_JSON='{"type":"remote","url":"http://127.0.0.1:49374/mcp","enabled":true}'
AI_MEMORY_MIN_VERSION="1.28.0"
AI_MEMORY_RELEASE_VERSION_EXPECTED="2.1.1"
AI_MEMORY_MACOS_AARCH64_SHA256_EXPECTED="1cc2acdbbd62cc7ecf6e1fe91515ea77786910b2c102f1fe8781aa6c0357eb64"
AI_MEMORY_LLM_PROFILE_EXPECTED="opencode-go-deepseek-v4.1-flash"
AI_MEMORY_LLM_PROVIDER_EXPECTED="opencode"
AI_MEMORY_LLM_MODEL_EXPECTED="deepseek-v4.1-flash"
ORCA_LAUNCH_DAEMON_SOURCE_FILE="$HOME/.config/orca-server/com.stablyai.orca-server.plist"
ORCA_LAUNCH_DAEMON_FILE="/Library/LaunchDaemons/com.stablyai.orca-server.plist"
ORCA_LAUNCH_DAEMON_LABEL="com.stablyai.orca-server"
ORCA_FIREWALL_LABEL="com.stablyai.orca-firewall"
ORCA_PF_CONFIG_FILE="/etc/pf.conf"
ORCA_PF_CONFIG_SOURCE_FILE="$HOME/.config/orca-server/pf.conf"
ORCA_PF_CONFIG_ROLLBACK_FILE="$HOME/.config/orca-server/pf.conf.without-orca"
ORCA_PF_CONFIG_DIGEST_FILE="$HOME/.config/orca-server/pf.conf.sha256"
ORCA_PF_ANCHOR_NAME="com.stablyai.orca-server"
ORCA_PF_ANCHOR_SOURCE_FILE="$HOME/.config/orca-server/com.stablyai.orca-server.pf"
ORCA_PF_ANCHOR_FILE="/etc/pf.anchors/com.stablyai.orca-server"
ORCA_FIREWALL_SCRIPT_SOURCE_FILE="$HOME/.config/orca-server/com.stablyai.orca-firewall.sh"
ORCA_FIREWALL_SCRIPT_FILE="/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-firewall.sh"
ORCA_SERVER_SCRIPT_SOURCE_FILE="$HOME/.config/orca-server/com.stablyai.orca-server.sh"
ORCA_SERVER_SCRIPT_FILE="/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-server.sh"
ORCA_GATE_EVIDENCE_FILE="/var/run/com.stablyai.orca-server.gate"
ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE="$HOME/.config/orca-server/com.stablyai.orca-firewall.plist"
ORCA_FIREWALL_LAUNCH_DAEMON_FILE="/Library/LaunchDaemons/com.stablyai.orca-firewall.plist"
BUN_MIN_VERSION="1.3.0"
LEARN_REPOSITORY_URL_EXPECTED="https://github.com/guisaliba/learn.git"
LEARN_BRANCH="main"
LEARN_INSTALL_DIR="$HOME/.local/share/opencode/learn"
LEARN_PLUGIN_SPEC="$LEARN_INSTALL_DIR"
LEARN_LEGACY_PLUGIN_BASE="github:guisaliba/learn"
LEARN_OLDER_PLUGIN_BASE="github:guisaliba/opencode-learn"
LEARN_MIN_OPENCODE_VERSION="1.18.22"
OPENCODE_TUI_THEME_EXPECTED="orng"
OPENCODE_TUI_SIDEBAR_KEYBIND_ID="session.sidebar.toggle"
OPENCODE_TUI_SIDEBAR_KEYBIND_EXPECTED="ctrl+b"
OPENCODE_TUI_BACKGROUND_KEYBIND_ID="session.background"
OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_ID="input.move.left"
OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_EXPECTED="left"
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

require_absent() {
  local path="$1"
  local needle="$2"
  if [[ ! -f "$path" ]]; then
    not_ok "cannot search missing file: $path"
    return
  fi
  if grep -qF -- "$needle" "$path"; then
    not_ok "unexpected '$needle': $path"
  else
    ok "absent '$needle': $path"
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
        ["github:guisaliba/opencode-learn#v0.0.1", {"textModel": "stale/model"}],
        ["github:guisaliba/learn#v0.0.1", {"textModel": "stale/model"}],
        "github:guisaliba/learn#main",
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
  require_json_value "$fixture_config" "model" "openai/gpt-5.6-sol-fast"
  require_json_value "$fixture_config" "agent.plan.model" "openai/gpt-5.6-sol-fast"
  require_json_array_count "$fixture_config" "instructions" "user-rules.md" "1"
  require_json_array_count "$fixture_config" "instructions" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" "1"
  require_json_array_count "$fixture_config" "plugin" "user/plugin" "1"
  require_json_array_count "$fixture_config" "plugin" "@plannotator/opencode@latest" "1"
  require_json_array_count "$fixture_config" "plugin" "$fixture_learn_plugin" "1"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    '["github:guisaliba/opencode-learn#v0.0.1",{"textModel":"stale/model"}]' \
    "0"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    '["github:guisaliba/learn#v0.0.1",{"textModel":"stale/model"}]' \
    "0"
  require_json_value "$fixture_config" "agent.general.model" "opencode-go/deepseek-v4.1-flash"
  require_json_value "$fixture_config" "agent.explore.model" "opencode-go/deepseek-v4.1-flash"
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
    require_json_value "$profile_config" "agent.general.model" "$(profile_field "$selected_profile" subagent)"
    require_json_value "$profile_config" "agent.explore.model" "$(profile_field "$selected_profile" subagent)"
  done

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

test_opencode_tui_json_merge() {
  local fixture_root fixture_home fixture_config fixture_learn_plugin first_config malformed_home malformed_config malformed_before malformed_log
  local keybinds_home keybinds_config keybinds_before keybinds_log
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  fixture_config="$fixture_home/.config/opencode/tui.json"
  fixture_learn_plugin="$fixture_home/.local/share/opencode/learn"
  first_config="$fixture_root/first-tui.json"
  mkdir -p "$(dirname "$fixture_config")"
  python3 - "$fixture_config" <<'PY'
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
    "plugin": [
        "user/tui-plugin",
        ["github:guisaliba/opencode-learn#v0.0.1", {"ipcRoot": "/stale"}],
        ["github:guisaliba/learn#v0.0.1", {"ipcRoot": "/stale"}],
        "github:guisaliba/learn#main",
    ],
}
Path(sys.argv[1]).write_text(json.dumps(config, indent=2) + "\n", encoding="utf-8")
PY

  if (
    HOME="$fixture_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    source "$REPO_DIR/apply.sh"
    merge_opencode_tui_json
  ) >/dev/null 2>&1; then
    ok "OpenCode TUI merge fixture applies"
  else
    not_ok "OpenCode TUI merge fixture failed"
  fi
  require_json_value "$fixture_config" "theme" "$OPENCODE_TUI_THEME_EXPECTED"
  require_json_array_count "$fixture_config" "plugin" "user/tui-plugin" "1"
  require_json_array_count "$fixture_config" "plugin" "$fixture_learn_plugin" "1"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    '["github:guisaliba/opencode-learn#v0.0.1",{"ipcRoot":"/stale"}]' \
    "0"
  require_json_array_item_count \
    "$fixture_config" \
    "plugin" \
    '["github:guisaliba/learn#v0.0.1",{"ipcRoot":"/stale"}]' \
    "0"

  require_json_keybind \
    "$fixture_config" \
    "$OPENCODE_TUI_SIDEBAR_KEYBIND_ID" \
    "\"$OPENCODE_TUI_SIDEBAR_KEYBIND_EXPECTED\""
  require_json_keybind \
    "$fixture_config" \
    "$OPENCODE_TUI_BACKGROUND_KEYBIND_ID" \
    "false"
  require_json_keybind \
    "$fixture_config" \
    "$OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_ID" \
    "\"$OPENCODE_TUI_INPUT_MOVE_LEFT_KEYBIND_EXPECTED\""
  require_json_keybind \
    "$fixture_config" \
    "command.palette.show" \
    '"ctrl+k"'

  cp "$fixture_config" "$first_config"
  if (
    HOME="$fixture_home"
    LEARN_INSTALL_DIR="$fixture_learn_plugin"
    source "$REPO_DIR/apply.sh"
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
    source "$REPO_DIR/apply.sh"
    merge_opencode_tui_json
  ) >"$malformed_log" 2>&1; then
    not_ok "invalid OpenCode TUI plugin structure was accepted"
  else
    ok "invalid OpenCode TUI plugin structure fails"
  fi
  require_same_file "$malformed_before" "$malformed_config"
  require_contains "$malformed_log" "Expected 'plugin' to be an array or string"

  keybinds_home="$fixture_root/keybinds-home"
  keybinds_config="$keybinds_home/.config/opencode/tui.json"
  keybinds_before="$fixture_root/keybinds-before.json"
  keybinds_log="$fixture_root/keybinds.log"
  mkdir -p "$(dirname "$keybinds_config")"
  printf '%s\n' '{"theme":"keep","keybinds":[]}' >"$keybinds_config"
  cp "$keybinds_config" "$keybinds_before"
  if (
    HOME="$keybinds_home"
    source "$REPO_DIR/apply.sh"
    merge_opencode_tui_json
  ) >"$keybinds_log" 2>&1; then
    not_ok "invalid OpenCode TUI keybinds structure was accepted"
  else
    ok "invalid OpenCode TUI keybinds structure fails"
  fi
  require_same_file "$keybinds_before" "$keybinds_config"
  require_contains "$keybinds_log" "Expected 'keybinds' to be an object"

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

test_ai_memory_env_file() {
  local fixture_root fixture_home fixture_env fixture_config env_before first_env
  local no_key_home no_key_env
  local selected_profile profile_home profile_env
  local invalid_profile invalid_index invalid_home invalid_env invalid_before invalid_log
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
  require_env_assignment "$fixture_env" "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED" "false"

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
    '  "install --cask google-chrome") mkdir -p "$GOOGLE_CHROME_APP_PATH"; exit 0 ;;' \
    '  *) exit 2 ;;' \
    'esac' \
    'chmod +x "$MACOS_TEST_BREW_PREFIX/bin/${2/python/python3}"' >"$stub_bin/brew"
  chmod +x "$stub_bin/uname" "$stub_bin/brew"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:$brew_prefix/bin:/bin"
    MACOS_TEST_BREW_PREFIX="$brew_prefix"
    MACOS_TEST_INSTALL_LOG="$install_log"
    GOOGLE_CHROME_APP_PATH="$fixture_root/Applications/Google Chrome.app"
    export HOME PATH MACOS_TEST_BREW_PREFIX MACOS_TEST_INSTALL_LOG GOOGLE_CHROME_APP_PATH
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
    install_orca() { printf '%s\n' orca-binary >>"$action_log"; }
    report_optional_ai_jail() { printf '%s\n' ai-jail >>"$action_log"; }
    verify_ai_memory_unauthenticated_loopback() { printf '%s\n' loopback >>"$action_log"; }
    setup_opencode() { printf '%s\n' opencode-config >>"$action_log"; }
    setup_ai_memory() { printf '%s\n' ai-memory-config >>"$action_log"; }
    setup_orca() { printf '%s\n' orca-service >>"$action_log"; }
    merge_opencode_shell_override() { printf '%s\n' shell >>"$action_log"; }
    configure_macos_bash_profile() { printf '%s\n' bash-profile >>"$action_log"; }
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
    version:opencode \
    ai-memory-binary \
    orca-binary \
    ai-jail \
    loopback \
    opencode-config \
    ai-memory-config \
    orca-service \
    shell \
    bash-profile \
    plugins \
    skills >"$expected_log"
  require_same_file "$expected_log" "$action_log"

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
  local fixture_root fixture_home aliases first_aliases stub_bin
  local ai_memory_log raw_log expected yolo_log managed_rc
  local malformed_home malformed_aliases malformed_before malformed_log
  local temp_source_home temp_source temp_source_aliases temp_source_first
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
  require_contains "$aliases" 'command ai-memory run opencode "$@"'
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
    'printf '\''%s\n'\'' "$@" >"$OPENCODE_TEST_AI_MEMORY_LOG"' \
    'exit "${OPENCODE_TEST_EXIT_STATUS:-0}"' >"$stub_bin/ai-memory"
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
  printf '%s\n' run opencode -c 'fixture task' >"$expected"
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

test_macos_orca_installation() {
  local fixture_root stub_bin install_log expected_log
  fixture_root="$(mktemp -d)"
  stub_bin="$fixture_root/bin"
  install_log="$fixture_root/brew.log"
  expected_log="$fixture_root/expected.log"
  mkdir -p "$stub_bin"
  : >"$install_log"

  printf '%s\n' \
    '#!/bin/bash' \
    'printf '\''%s\n'\'' "$*" >>"$ORCA_TEST_INSTALL_LOG"' \
    '[[ "$*" == "install --cask stablyai/orca/orca" ]] || exit 2' \
    'printf '\''#!/bin/bash\nexit 0\n'\'' >"$ORCA_TEST_BIN/orca"' \
    'chmod +x "$ORCA_TEST_BIN/orca"' >"$stub_bin/brew"
  chmod +x "$stub_bin/brew"

  if (
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_TEST_BIN="$stub_bin"
    ORCA_TEST_INSTALL_LOG="$install_log"
    export PATH ORCA_TEST_BIN ORCA_TEST_INSTALL_LOG
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    install_orca
    install_orca
  ) >/dev/null 2>&1; then
    ok "macOS Orca cask installation applies twice"
  else
    not_ok "macOS Orca cask installation fixture failed"
  fi
  printf '%s\n' 'install --cask stablyai/orca/orca' >"$expected_log"
  require_same_file "$expected_log" "$install_log"

  : >"$install_log"
  if (
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_TEST_BIN="$stub_bin"
    ORCA_TEST_INSTALL_LOG="$install_log"
    export PATH ORCA_TEST_BIN ORCA_TEST_INSTALL_LOG
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Linux; }
    install_orca
  ) >/dev/null 2>&1; then
    ok "Linux skips Orca installation"
  else
    not_ok "Linux Orca installation no-op failed"
  fi
  require_empty_file "$install_log"

  rm -rf -- "$fixture_root"
}

test_macos_orca_launch_daemon() {
  local fixture_root fixture_home stub_bin executable daemon_source daemon_file install_log
  local launch_log username group server_source server_file
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  executable="$stub_bin/orca"
  daemon_source="$fixture_home/.config/orca-server/com.stablyai.orca-server.plist"
  daemon_file="$fixture_root/Library/LaunchDaemons/com.stablyai.orca-server.plist"
  server_source="$fixture_home/.config/orca-server/com.stablyai.orca-server.sh"
  server_file="$fixture_root/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-server.sh"
  install_log="$fixture_root/install-required.log"
  launch_log="$fixture_root/launchctl.log"
  username="$(id -un)"
  group="$(id -gn)"
  mkdir -p "$stub_bin"
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$executable"
  chmod +x "$executable"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    export HOME PATH ORCA_LAUNCH_DAEMON_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    install_orca_launch_daemon
  ) >/dev/null 2>&1; then
    ok "macOS Orca LaunchDaemon source is generated"
  else
    not_ok "macOS Orca LaunchDaemon source generation failed"
  fi
  require_file "$daemon_source"
  require_file_mode "$daemon_source" "600"
  require_file_mode "$fixture_home/Library/Logs/orca-server" "700"
  require_file_mode "$fixture_home/Library/Logs/orca-server/stdout.log" "600"
  require_file_mode "$fixture_home/Library/Logs/orca-server/stderr.log" "600"
  if python3 - "$daemon_source" "$executable" "$fixture_home" "$username" "$group" "$server_file" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
executable = sys.argv[2]
home = sys.argv[3]
username = sys.argv[4]
group = sys.argv[5]
server_file = sys.argv[6]
with path.open("rb") as stream:
    config = plistlib.load(stream)

assert config == {
    "Label": "com.stablyai.orca-server",
    "UserName": username,
    "GroupName": group,
    "ProgramArguments": [
        "/bin/bash",
        server_file,
        executable,
        "serve",
        "--port",
        "6768",
        "--pairing-address",
        "aurealabs-mac-mini-m4.taildc6550.ts.net",
        "--no-pairing",
    ],
    "RunAtLoad": True,
    "KeepAlive": True,
    "ThrottleInterval": 10,
    "WorkingDirectory": home,
    "EnvironmentVariables": {
        "HOME": home,
        "PATH": f"{home}/.opencode/bin:{home}/.local/bin:{home}/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
        "USER": username,
        "LOGNAME": username,
    },
    "StandardOutPath": f"{home}/Library/Logs/orca-server/stdout.log",
    "StandardErrorPath": f"{home}/Library/Logs/orca-server/stderr.log",
}
PY
  then
    ok "macOS Orca LaunchDaemon has the required runtime contract"
  else
    not_ok "macOS Orca LaunchDaemon has incorrect content"
  fi

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    export HOME PATH ORCA_LAUNCH_DAEMON_SOURCE_FILE ORCA_LAUNCH_DAEMON_FILE
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    start_orca_launch_daemon
  ) >"$install_log" 2>&1; then
    not_ok "missing macOS Orca LaunchDaemon was accepted"
  else
    ok "missing macOS Orca LaunchDaemon requires privileged installation"
  fi
  require_contains "$install_log" "sudo bash"
  require_contains "$install_log" "install-privileged.sh"

  mkdir -p "$(dirname "$daemon_file")"
  python3 - "$daemon_source" "$daemon_file" <<'PY'
import plistlib
import sys
from pathlib import Path

source = Path(sys.argv[1])
installed = Path(sys.argv[2])
installed.write_bytes(
    plistlib.dumps(plistlib.loads(source.read_bytes()), fmt=plistlib.FMT_XML, sort_keys=True)
)
PY
  printf '%s\n' 'fixture-preflight' >"$server_source"
  mkdir -p "$(dirname "$server_file")"
  cp "$server_source" "$server_file"
  printf '%s\n' \
    '#!/bin/bash' \
    '[[ "$1" == -f ]] && { [[ -e "$3" ]] || exit 1; case "$3" in *.sh) printf '\''root:wheel:755\n'\'' ;; *) printf '\''root:wheel:644\n'\'' ;; esac; exit 0; }' \
    'exec /usr/bin/stat "$@"' >"$stub_bin/stat"
  printf '%s\n' \
    '#!/bin/bash' \
    'printf '\''%s\n'\'' "$*" >>"$ORCA_TEST_LAUNCH_LOG"' \
    '[[ "$1" == print ]]' >"$stub_bin/launchctl"
  printf '%s\n' \
    '#!/bin/bash' \
    'exit "${ORCA_TEST_LSOF_RC:-0}"' >"$stub_bin/lsof"
  chmod +x "$stub_bin/stat" "$stub_bin/launchctl" "$stub_bin/lsof"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_TEST_LSOF_RC="1"
    export HOME PATH ORCA_LAUNCH_DAEMON_SOURCE_FILE ORCA_LAUNCH_DAEMON_FILE ORCA_TEST_LSOF_RC
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    start_orca_launch_daemon
  ) >"$install_log" 2>&1; then
    not_ok "active macOS Orca LaunchDaemon without a listener was accepted"
  else
    ok "active macOS Orca LaunchDaemon without a listener is rejected"
  fi
  require_contains "$install_log" "not listening on TCP 6768"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_TEST_LAUNCH_LOG="$launch_log"
    ORCA_TEST_LSOF_RC="0"
    export HOME PATH ORCA_LAUNCH_DAEMON_SOURCE_FILE ORCA_LAUNCH_DAEMON_FILE ORCA_TEST_LAUNCH_LOG ORCA_TEST_LSOF_RC
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    start_orca_launch_daemon
    start_orca_launch_daemon
  ) >/dev/null 2>&1; then
    ok "active macOS Orca LaunchDaemon satisfies repeated setup"
  else
    not_ok "active macOS Orca LaunchDaemon setup failed"
  fi
  require_text_count "$launch_log" "print system/com.stablyai.orca-server" "2"

  rm -rf -- "$fixture_root"
}

test_macos_orca_firewall() {
  local fixture_root fixture_home stub_bin pf_config pf_config_source pf_config_rollback pf_config_digest anchor_source anchor_file
  local gate_source gate_file server_source server_file install_script evidence_file daemon_source daemon_file install_log launch_log pfctl_log live_rules expected_rules
  local boot_id expected_hash pf_config_hash other_hash orca_daemon_file install_cmd_log
  local main_rules main_rules_after pf_status_file
  fixture_root="$(mktemp -d)"
  fixture_home="$fixture_root/home"
  stub_bin="$fixture_root/bin"
  pf_config="$fixture_root/etc/pf.conf"
  pf_config_source="$fixture_home/.config/orca-server/pf.conf"
  pf_config_rollback="$fixture_home/.config/orca-server/pf.conf.without-orca"
  pf_config_digest="$fixture_home/.config/orca-server/pf.conf.sha256"
  anchor_source="$fixture_home/.config/orca-server/com.stablyai.orca-server.pf"
  anchor_file="$fixture_root/etc/pf.anchors/com.stablyai.orca-server"
  gate_source="$fixture_home/.config/orca-server/com.stablyai.orca-firewall.sh"
  gate_file="$fixture_home/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-firewall.sh"
  server_source="$fixture_home/.config/orca-server/com.stablyai.orca-server.sh"
  server_file="$fixture_home/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-server.sh"
  install_script="$fixture_home/.config/orca-server/install-privileged.sh"
  evidence_file="$fixture_root/run/com.stablyai.orca-server.gate"
  daemon_source="$fixture_home/.config/orca-server/com.stablyai.orca-firewall.plist"
  daemon_file="$fixture_root/Library/LaunchDaemons/com.stablyai.orca-firewall.plist"
  install_log="$fixture_root/install-required.log"
  launch_log="$fixture_root/launchctl.log"
  pfctl_log="$fixture_root/pfctl.log"
  install_cmd_log="$fixture_root/install-commands.log"
  live_rules="$fixture_root/live-rules"
  expected_rules="$fixture_root/expected-rules"
  main_rules="$fixture_root/main-rules"
  main_rules_after="$fixture_root/main-rules-after"
  pf_status_file="$fixture_root/pf-status"
  boot_id="FIXTURE-BOOT-SESSION"
  mkdir -p "$stub_bin" "$(dirname "$pf_config")" "$(dirname "$evidence_file")" "$(dirname "$anchor_file")"
  printf '%s\n' \
    '# preserve system PF rules' \
    'scrub-anchor "com.apple/*"' \
    'nat-anchor "com.apple/*"' \
    'rdr-anchor "com.apple/*"' \
    'dummynet-anchor "com.apple/*"' \
    'anchor "com.apple/*"' \
    "load anchor \"com.apple\" from \"$fixture_root/etc/pf.anchors/com.apple\"" \
    'pass in quick proto tcp from any to any port 6768' >"$pf_config"
  printf '%s\n' 'pass in proto tcp from any to any port 22' \
    >"$fixture_root/etc/pf.anchors/com.apple"
  cp "$pf_config" "$fixture_root/pf-config.original"
  printf '%s\n' \
    'pass in quick on utun* inet proto tcp from 100.64.0.0/10 to any port = 6768 flags S/SA keep state' \
    'pass in quick on utun* inet6 proto tcp from fd7a:115c:a1e0::/48 to any port = 6768 flags S/SA keep state' \
    'block drop in quick proto tcp from any to any port = 6768' >"$expected_rules"
  cp "$expected_rules" "$live_rules"
  printf '%s\n' \
    'anchor "com.stablyai.orca-server" all' \
    'anchor "/*" all' \
    'pass in quick proto tcp from any to any port 22 flags S/SA keep state' >"$main_rules"
  cp "$main_rules" "$main_rules_after"
  orca_daemon_file="/Library/LaunchDaemons/com.stablyai.orca-server.plist"
  expected_hash="$(python3 - "$expected_rules" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
  pf_config_hash="$(python3 - "$pf_config" <<'PY'
import hashlib
import sys
from pathlib import Path

print(hashlib.sha256(Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)"
  other_hash="0000000000000000000000000000000000000000000000000000000000000000"

  printf '%s\n' \
    '#!/bin/bash' \
    'printf '\''%s\n'\'' "$*" >>"$ORCA_TEST_PFCTL_LOG"' \
    'case "$1" in' \
    '  -s)' \
    '    case "$2" in' \
    '      info) printf '\''Status: %s\n'\'' "$(cat "$ORCA_TEST_PF_STATUS_FILE")"; exit 0 ;;' \
    '      rules) cat "$ORCA_TEST_MAIN_RULES"; exit 0 ;;' \
    '    esac ;;' \
    '  -sr) cat "$ORCA_TEST_MAIN_RULES"; exit 0 ;;' \
    '  -E) rc="${ORCA_TEST_PF_ENABLE_RC:-0}"; [[ "$rc" == "0" ]] && printf '\''Enabled'\'' >"$ORCA_TEST_PF_STATUS_FILE"; exit "$rc" ;;' \
    '  -f) rc="${ORCA_TEST_PF_LOAD_RC:-0}"; [[ "$rc" == "0" && -n "${ORCA_TEST_MAIN_RULES_AFTER:-}" ]] && cp "$ORCA_TEST_MAIN_RULES_AFTER" "$ORCA_TEST_MAIN_RULES"; exit "$rc" ;;' \
    '  -a)' \
    '    case "$3" in' \
    '      -sr) cat "$ORCA_TEST_LIVE_RULES"; exit 0 ;;' \
    '      -nvf) cat "$ORCA_TEST_EXPECTED_RULES"; exit 0 ;;' \
    '    esac ;;' \
    'esac' \
    'exit 2' >"$stub_bin/pfctl"
  printf '%s\n' \
    '#!/bin/bash' \
    'printf '\''%s\n'\'' "$*" >>"$ORCA_TEST_LAUNCH_LOG"' \
    'case "$1" in' \
    '  print) exit "${ORCA_TEST_LAUNCH_PRINT_RC:-1}" ;;' \
    'esac' \
    'exit 0' >"$stub_bin/launchctl"
  printf '%s\n' \
    '#!/bin/bash' \
    '[[ "$1" == -n && "$2" == kern.bootsessionuuid ]] && { printf '\''%s\n'\'' "$ORCA_TEST_BOOT_ID"; exit 0; }' \
    'exit 2' >"$stub_bin/sysctl"
  printf '%s\n' \
    '#!/bin/bash' \
    'if [[ "$1" == -f ]]; then' \
    '  [[ -e "$3" ]] || exit 1' \
    '  case "$3" in' \
    '    *.sh) printf '\''root:wheel:755\n'\'' ;;' \
    '    *) printf '\''root:wheel:644\n'\'' ;;' \
    '  esac' \
    '  exit 0' \
    'fi' \
    'exec /usr/bin/stat "$@"' >"$stub_bin/stat"
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$stub_bin/chown"
  printf '%s\n' \
    '#!/usr/bin/env bash' \
    'if [[ "${3:-}" != "" ]]; then' \
    '  exec python3 -c "import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],\"rb\").read()).hexdigest())" "$3"' \
    'fi' \
    'exec python3 -c "import hashlib,sys; print(hashlib.sha256(sys.stdin.buffer.read()).hexdigest())"' >"$stub_bin/shasum"
  printf '%s\n' \
    '#!/bin/bash' \
    'printf '\''install %s\n'\'' "$*" >>"$ORCA_TEST_INSTALL_CMD_LOG"' \
    'if [[ "${ORCA_TEST_INSTALL_PUBLISH:-0}" == "1" && "$*" == *com.stablyai.orca-server.pf* ]]; then' \
    '  hash="$(shasum -a 256 "$ORCA_TEST_EXPECTED_RULES" | awk '\''{print $1}'\'')"' \
    '  printf '\''bootsession=%s\nanchor_sha256=%s\n'\'' "$ORCA_TEST_BOOT_ID" "$hash" >"$ORCA_TEST_EVIDENCE_FILE"' \
    'fi' \
    'exit 0' >"$stub_bin/install"
  printf '%s\n' '#!/bin/bash' 'exit 0' >"$stub_bin/sleep"
  chmod +x \
    "$stub_bin/pfctl" \
    "$stub_bin/launchctl" \
    "$stub_bin/sysctl" \
    "$stub_bin/stat" \
    "$stub_bin/chown" \
    "$stub_bin/shasum" \
    "$stub_bin/install" \
    "$stub_bin/sleep"

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_PF_CONFIG_FILE="$pf_config"
    ORCA_PF_CONFIG_SOURCE_FILE="$pf_config_source"
    ORCA_PF_CONFIG_ROLLBACK_FILE="$pf_config_rollback"
    ORCA_PF_CONFIG_DIGEST_FILE="$pf_config_digest"
    ORCA_PF_ANCHOR_SOURCE_FILE="$anchor_source"
    ORCA_PF_ANCHOR_FILE="$anchor_file"
    ORCA_FIREWALL_SCRIPT_SOURCE_FILE="$gate_source"
    ORCA_FIREWALL_SCRIPT_FILE="$gate_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_INSTALL_SCRIPT_FILE="$install_script"
    ORCA_GATE_EVIDENCE_FILE="$evidence_file"
    ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_FIREWALL_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_PFCTL_BIN="$stub_bin/pfctl"
    ORCA_LAUNCHCTL_BIN="$stub_bin/launchctl"
    ORCA_SYSCTL_BIN="$stub_bin/sysctl"
    ORCA_SHASUM_BIN="$stub_bin/shasum"
    ORCA_CHOWN_BIN="$stub_bin/chown"
    export HOME PATH ORCA_PF_CONFIG_FILE ORCA_PF_CONFIG_SOURCE_FILE ORCA_PF_CONFIG_ROLLBACK_FILE
    export ORCA_PF_CONFIG_DIGEST_FILE ORCA_PF_ANCHOR_SOURCE_FILE ORCA_PF_ANCHOR_FILE
    export ORCA_FIREWALL_SCRIPT_SOURCE_FILE ORCA_FIREWALL_SCRIPT_FILE ORCA_GATE_EVIDENCE_FILE
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    export ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE ORCA_FIREWALL_LAUNCH_DAEMON_FILE
    export ORCA_PFCTL_BIN ORCA_LAUNCHCTL_BIN ORCA_SYSCTL_BIN ORCA_SHASUM_BIN ORCA_CHOWN_BIN
    source "$REPO_DIR/apply.sh"
    install_orca_firewall_sources
    install_orca_firewall_sources
  ) >/dev/null 2>&1; then
    ok "macOS Orca PF and gate sources apply twice"
  else
    not_ok "macOS Orca PF and gate source generation failed"
  fi
  require_file_mode "$pf_config_source" "600"
  require_file_mode "$pf_config_rollback" "600"
  require_contains "$pf_config_rollback" "# preserve system PF rules"
  require_file_mode "$pf_config_digest" "600"
  require_contains "$pf_config_digest" "$pf_config_hash"
  require_file_mode "$anchor_source" "600"
  require_file_mode "$gate_source" "600"
  require_file_mode "$server_source" "600"
  require_file_mode "$daemon_source" "600"
  require_file_mode "$install_script" "700"
  require_contains "$pf_config_source" "# preserve system PF rules"
  require_text_count "$pf_config_source" "# >>> guisaliba/agents Orca firewall >>>" "1"
  require_contains "$anchor_source" "pass in quick on utun* inet proto tcp from 100.64.0.0/10 to any port 6768"
  require_contains "$anchor_source" "pass in quick on utun* inet6 proto tcp from fd7a:115c:a1e0::/48 to any port 6768"
  require_contains "$anchor_source" "block drop in quick proto tcp from any to any port 6768"
  require_same_file "$fixture_root/pf-config.original" "$pf_config_rollback"
  if python3 - "$pf_config_source" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
translation = text.index('dummynet-anchor "com.apple/*"')
block = text.index("# >>> guisaliba/agents Orca firewall >>>")
orca = text.index('\nanchor "com.stablyai.orca-server"\n')
apple = text.index('\nanchor "com.apple/*"\n')
rule = text.index("pass in quick proto tcp from any to any port 6768")
raise SystemExit(0 if translation < block < orca < apple < rule else 1)
PY
  then
    ok "macOS Orca anchor is placed at the start of the filtering section"
  else
    not_ok "macOS Orca anchor is not placed at the start of the filtering section"
  fi
  require_contains "$install_script" "set -Eeuo pipefail"
  require_contains "$install_script" "$pf_config_hash"
  require_contains "$install_script" "install -o root -g wheel -m 0755"
  require_contains "$install_script" "install -o root -g wheel -m 0644"
  require_contains "$install_script" "disable \"system/\$ORCA_LABEL\""
  require_contains "$install_script" "bootstrap system \"\$FIREWALL_PLIST\""
  require_contains "$install_script" "kickstart -k \"system/\$FIREWALL_LABEL\""
  require_contains "$gate_source" "-s info"
  require_contains "$gate_source" "-a \"\$ANCHOR_NAME\" -sr"
  require_contains "$gate_source" "-a \"\$ANCHOR_NAME\" -nvf"
  require_contains "$gate_source" "Status: Enabled"
  require_contains "$gate_source" "kern.bootsessionuuid"
  require_contains "$gate_source" "bootsession=%s"
  require_contains "$gate_source" "anchor_sha256=%s"
  require_contains "$gate_source" "disable \"system/\$ORCA_LABEL\""
  require_contains "$gate_source" "kill SIGTERM \"system/\$ORCA_LABEL\""
  require_contains "$gate_source" "enable \"system/\$ORCA_LABEL\""
  require_contains "$gate_source" "bootstrap system \"\$ORCA_DAEMON_FILE\""
  require_contains "$gate_source" "kickstart \"system/\$ORCA_LABEL\""
  require_contains "$server_source" "orca-server-preflight"
  require_contains "$server_source" "missing firewall gate evidence"
  require_contains "$server_source" "belongs to another boot"
  require_contains "$server_source" "does not match the expected anchor"
  require_contains "$server_source" '-nvf "$ANCHOR_FILE"'
  require_contains "$server_source" 'exec "$@"'
  if python3 - "$daemon_source" "$fixture_home" "$gate_file" <<'PY'
import plistlib
import sys
from pathlib import Path

with Path(sys.argv[1]).open("rb") as stream:
    config = plistlib.load(stream)
home = Path(sys.argv[2])
gate_file = sys.argv[3]

assert config == {
    "Label": "com.stablyai.orca-firewall",
    "ProgramArguments": ["/bin/bash", gate_file],
    "RunAtLoad": True,
    "StartInterval": 60,
    "StandardOutPath": str(home / "Library/Logs/orca-server/firewall-stdout.log"),
    "StandardErrorPath": str(home / "Library/Logs/orca-server/firewall-stderr.log"),
}
PY
  then
    ok "macOS Orca firewall gate LaunchDaemon has the required runtime contract"
  else
    not_ok "macOS Orca firewall gate LaunchDaemon has incorrect content"
  fi

  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_PF_CONFIG_FILE="$pf_config"
    ORCA_PF_CONFIG_SOURCE_FILE="$pf_config_source"
    ORCA_PF_CONFIG_ROLLBACK_FILE="$pf_config_rollback"
    ORCA_PF_CONFIG_DIGEST_FILE="$pf_config_digest"
    ORCA_PF_ANCHOR_SOURCE_FILE="$anchor_source"
    ORCA_PF_ANCHOR_FILE="$anchor_file"
    ORCA_FIREWALL_SCRIPT_SOURCE_FILE="$gate_source"
    ORCA_FIREWALL_SCRIPT_FILE="$gate_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_INSTALL_SCRIPT_FILE="$install_script"
    ORCA_GATE_EVIDENCE_FILE="$evidence_file"
    ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_FIREWALL_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_PFCTL_BIN="$stub_bin/pfctl"
    ORCA_LAUNCHCTL_BIN="$stub_bin/launchctl"
    ORCA_SYSCTL_BIN="$stub_bin/sysctl"
    ORCA_SHASUM_BIN="$stub_bin/shasum"
    ORCA_CHOWN_BIN="$stub_bin/chown"
    export HOME PATH ORCA_PF_CONFIG_FILE ORCA_PF_CONFIG_SOURCE_FILE ORCA_PF_CONFIG_ROLLBACK_FILE
    export ORCA_PF_CONFIG_DIGEST_FILE ORCA_PF_ANCHOR_SOURCE_FILE ORCA_PF_ANCHOR_FILE
    export ORCA_FIREWALL_SCRIPT_SOURCE_FILE ORCA_FIREWALL_SCRIPT_FILE ORCA_GATE_EVIDENCE_FILE
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    export ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE ORCA_FIREWALL_LAUNCH_DAEMON_FILE
    export ORCA_PFCTL_BIN ORCA_LAUNCHCTL_BIN ORCA_SYSCTL_BIN ORCA_SHASUM_BIN ORCA_CHOWN_BIN
    source "$REPO_DIR/apply.sh"
    start_orca_firewall
  ) >"$install_log" 2>&1; then
    not_ok "missing macOS Orca firewall was accepted"
  else
    ok "missing macOS Orca firewall requires privileged installation"
  fi
  require_contains "$install_log" "sudo bash"
  require_contains "$install_log" "$install_script"

  mkdir -p "$(dirname "$anchor_file")" "$(dirname "$daemon_file")" "$(dirname "$gate_file")"
  cp "$pf_config_source" "$pf_config"
  cp "$anchor_source" "$anchor_file"
  cp "$gate_source" "$gate_file"
  cp "$daemon_source" "$daemon_file"

  printf '%s\n' "bootsession=OTHER-BOOT-SESSION" "anchor_sha256=$expected_hash" >"$evidence_file"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_PF_CONFIG_FILE="$pf_config"
    ORCA_PF_CONFIG_SOURCE_FILE="$pf_config_source"
    ORCA_PF_CONFIG_ROLLBACK_FILE="$pf_config_rollback"
    ORCA_PF_CONFIG_DIGEST_FILE="$pf_config_digest"
    ORCA_PF_ANCHOR_SOURCE_FILE="$anchor_source"
    ORCA_PF_ANCHOR_FILE="$anchor_file"
    ORCA_FIREWALL_SCRIPT_SOURCE_FILE="$gate_source"
    ORCA_FIREWALL_SCRIPT_FILE="$gate_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_INSTALL_SCRIPT_FILE="$install_script"
    ORCA_GATE_EVIDENCE_FILE="$evidence_file"
    ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_FIREWALL_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_PFCTL_BIN="$stub_bin/pfctl"
    ORCA_LAUNCHCTL_BIN="$stub_bin/launchctl"
    ORCA_SYSCTL_BIN="$stub_bin/sysctl"
    ORCA_SHASUM_BIN="$stub_bin/shasum"
    ORCA_CHOWN_BIN="$stub_bin/chown"
    ORCA_TEST_EXPECTED_RULES="$expected_rules"
    ORCA_TEST_BOOT_ID="$boot_id"
    ORCA_TEST_LAUNCH_PRINT_RC="0"
    export HOME PATH ORCA_PF_CONFIG_FILE ORCA_PF_CONFIG_SOURCE_FILE ORCA_PF_CONFIG_ROLLBACK_FILE
    export ORCA_PF_CONFIG_DIGEST_FILE ORCA_PF_ANCHOR_SOURCE_FILE ORCA_PF_ANCHOR_FILE
    export ORCA_FIREWALL_SCRIPT_SOURCE_FILE ORCA_FIREWALL_SCRIPT_FILE ORCA_GATE_EVIDENCE_FILE
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    export ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE ORCA_FIREWALL_LAUNCH_DAEMON_FILE
    export ORCA_PFCTL_BIN ORCA_LAUNCHCTL_BIN ORCA_SYSCTL_BIN ORCA_SHASUM_BIN ORCA_CHOWN_BIN
    export ORCA_TEST_EXPECTED_RULES ORCA_TEST_BOOT_ID ORCA_TEST_LAUNCH_PRINT_RC
    source "$REPO_DIR/apply.sh"
    orca_expected_anchor_rules() { cat "$ORCA_TEST_EXPECTED_RULES"; }
    orca_boot_identifier() { printf '%s\n' "$ORCA_TEST_BOOT_ID"; }
    start_orca_firewall
  ) >"$install_log" 2>&1; then
    not_ok "stale firewall gate evidence from another boot was accepted"
  else
    ok "stale firewall gate evidence from another boot is rejected"
  fi
  require_contains "$install_log" "current-boot"

  printf '%s\n' "bootsession=$boot_id" "anchor_sha256=$other_hash" >"$evidence_file"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_PF_CONFIG_FILE="$pf_config"
    ORCA_PF_CONFIG_SOURCE_FILE="$pf_config_source"
    ORCA_PF_CONFIG_ROLLBACK_FILE="$pf_config_rollback"
    ORCA_PF_CONFIG_DIGEST_FILE="$pf_config_digest"
    ORCA_PF_ANCHOR_SOURCE_FILE="$anchor_source"
    ORCA_PF_ANCHOR_FILE="$anchor_file"
    ORCA_FIREWALL_SCRIPT_SOURCE_FILE="$gate_source"
    ORCA_FIREWALL_SCRIPT_FILE="$gate_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_INSTALL_SCRIPT_FILE="$install_script"
    ORCA_GATE_EVIDENCE_FILE="$evidence_file"
    ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_FIREWALL_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_PFCTL_BIN="$stub_bin/pfctl"
    ORCA_LAUNCHCTL_BIN="$stub_bin/launchctl"
    ORCA_SYSCTL_BIN="$stub_bin/sysctl"
    ORCA_SHASUM_BIN="$stub_bin/shasum"
    ORCA_CHOWN_BIN="$stub_bin/chown"
    ORCA_TEST_EXPECTED_RULES="$expected_rules"
    ORCA_TEST_BOOT_ID="$boot_id"
    ORCA_TEST_LAUNCH_PRINT_RC="0"
    export HOME PATH ORCA_PF_CONFIG_FILE ORCA_PF_CONFIG_SOURCE_FILE ORCA_PF_CONFIG_ROLLBACK_FILE
    export ORCA_PF_CONFIG_DIGEST_FILE ORCA_PF_ANCHOR_SOURCE_FILE ORCA_PF_ANCHOR_FILE
    export ORCA_FIREWALL_SCRIPT_SOURCE_FILE ORCA_FIREWALL_SCRIPT_FILE ORCA_GATE_EVIDENCE_FILE
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    export ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE ORCA_FIREWALL_LAUNCH_DAEMON_FILE
    export ORCA_PFCTL_BIN ORCA_LAUNCHCTL_BIN ORCA_SYSCTL_BIN ORCA_SHASUM_BIN ORCA_CHOWN_BIN
    export ORCA_TEST_EXPECTED_RULES ORCA_TEST_BOOT_ID ORCA_TEST_LAUNCH_PRINT_RC
    source "$REPO_DIR/apply.sh"
    orca_expected_anchor_rules() { cat "$ORCA_TEST_EXPECTED_RULES"; }
    orca_boot_identifier() { printf '%s\n' "$ORCA_TEST_BOOT_ID"; }
    start_orca_firewall
  ) >"$install_log" 2>&1; then
    not_ok "firewall gate evidence with a stale anchor hash was accepted"
  else
    ok "firewall gate evidence with a stale anchor hash is rejected"
  fi

  printf '%s\n' "bootsession=$boot_id" "anchor_sha256=$expected_hash" >"$evidence_file"
  : >"$launch_log"
  if (
    HOME="$fixture_home"
    PATH="$stub_bin:/usr/bin:/bin"
    ORCA_PF_CONFIG_FILE="$pf_config"
    ORCA_PF_CONFIG_SOURCE_FILE="$pf_config_source"
    ORCA_PF_CONFIG_ROLLBACK_FILE="$pf_config_rollback"
    ORCA_PF_CONFIG_DIGEST_FILE="$pf_config_digest"
    ORCA_PF_ANCHOR_SOURCE_FILE="$anchor_source"
    ORCA_PF_ANCHOR_FILE="$anchor_file"
    ORCA_FIREWALL_SCRIPT_SOURCE_FILE="$gate_source"
    ORCA_FIREWALL_SCRIPT_FILE="$gate_file"
    ORCA_SERVER_SCRIPT_SOURCE_FILE="$server_source"
    ORCA_SERVER_SCRIPT_FILE="$server_file"
    ORCA_INSTALL_SCRIPT_FILE="$install_script"
    ORCA_GATE_EVIDENCE_FILE="$evidence_file"
    ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE="$daemon_source"
    ORCA_FIREWALL_LAUNCH_DAEMON_FILE="$daemon_file"
    ORCA_PFCTL_BIN="$stub_bin/pfctl"
    ORCA_LAUNCHCTL_BIN="$stub_bin/launchctl"
    ORCA_SYSCTL_BIN="$stub_bin/sysctl"
    ORCA_SHASUM_BIN="$stub_bin/shasum"
    ORCA_CHOWN_BIN="$stub_bin/chown"
    ORCA_TEST_EXPECTED_RULES="$expected_rules"
    ORCA_TEST_BOOT_ID="$boot_id"
    ORCA_TEST_LAUNCH_PRINT_RC="0"
    ORCA_TEST_LAUNCH_LOG="$launch_log"
    export HOME PATH ORCA_PF_CONFIG_FILE ORCA_PF_CONFIG_SOURCE_FILE ORCA_PF_CONFIG_ROLLBACK_FILE
    export ORCA_PF_CONFIG_DIGEST_FILE ORCA_PF_ANCHOR_SOURCE_FILE ORCA_PF_ANCHOR_FILE
    export ORCA_FIREWALL_SCRIPT_SOURCE_FILE ORCA_FIREWALL_SCRIPT_FILE ORCA_GATE_EVIDENCE_FILE
    export ORCA_SERVER_SCRIPT_SOURCE_FILE ORCA_SERVER_SCRIPT_FILE ORCA_INSTALL_SCRIPT_FILE
    export ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE ORCA_FIREWALL_LAUNCH_DAEMON_FILE
    export ORCA_PFCTL_BIN ORCA_LAUNCHCTL_BIN ORCA_SYSCTL_BIN ORCA_SHASUM_BIN ORCA_CHOWN_BIN
    export ORCA_TEST_EXPECTED_RULES ORCA_TEST_BOOT_ID ORCA_TEST_LAUNCH_LOG ORCA_TEST_LAUNCH_PRINT_RC
    source "$REPO_DIR/apply.sh"
    orca_expected_anchor_rules() { cat "$ORCA_TEST_EXPECTED_RULES"; }
    orca_boot_identifier() { printf '%s\n' "$ORCA_TEST_BOOT_ID"; }
    start_orca_firewall
    start_orca_firewall
  ) >/dev/null 2>&1; then
    ok "active macOS Orca firewall gate satisfies repeated setup"
  else
    not_ok "active macOS Orca firewall gate setup failed"
  fi
  require_text_count "$launch_log" "print system/com.stablyai.orca-firewall" "2"

  run_orca_gate() {
    local status="${1:-Enabled}"
    printf '%s' "$status" >"$pf_status_file"
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_LAUNCH_LOG="$launch_log" \
      ORCA_TEST_LIVE_RULES="$live_rules" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_MAIN_RULES="$main_rules" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      ORCA_TEST_PF_STATUS_FILE="$pf_status_file" \
      ORCA_TEST_PF_LOAD_RC="${2:-0}" \
      ORCA_TEST_PF_ENABLE_RC="${3:-0}" \
      ORCA_TEST_LAUNCH_PRINT_RC="${4:-1}" \
      bash "$gate_source"
  }

  write_orca_gate_evidence() {
    printf 'bootsession=%s\nanchor_sha256=%s\n' "$boot_id" "$expected_hash" >"$evidence_file"
  }

  : >"$pfctl_log"
  : >"$launch_log"
  if run_orca_gate Enabled >/dev/null 2>&1 && \
    [[ -f "$evidence_file" ]] && \
    grep -qF "bootsession=$boot_id" "$evidence_file" && \
    grep -qF "anchor_sha256=$expected_hash" "$evidence_file" && \
    grep -qF "enable system/com.stablyai.orca-server" "$launch_log" && \
    grep -qF "bootstrap system $orca_daemon_file" "$launch_log" && \
    grep -qF "kickstart system/com.stablyai.orca-server" "$launch_log"; then
    ok "healthy gate publishes evidence and starts Orca"
  else
    not_ok "healthy gate did not publish evidence or start Orca"
  fi
  printf '%s\n' \
    "-a com.stablyai.orca-server -nvf $anchor_file" \
    "-s info" \
    "-a com.stablyai.orca-server -sr" \
    "-sr" >"$fixture_root/expected-pfctl.log"
  require_same_file "$fixture_root/expected-pfctl.log" "$pfctl_log"
  if grep -qF -- "-f " "$pfctl_log"; then
    not_ok "healthy gate reloaded the system PF configuration"
  else
    ok "healthy gate did not reload the system PF configuration"
  fi

  : >"$pfctl_log"
  : >"$launch_log"
  if run_orca_gate Disabled >/dev/null 2>&1; then
    ok "gate loads and enables PF when it is disabled"
  else
    not_ok "gate failed to load and enable disabled PF"
  fi
  require_contains "$pfctl_log" "-f $pf_config"
  require_contains "$pfctl_log" "-E"

  : >"$pfctl_log"
  : >"$launch_log"
  write_orca_gate_evidence
  if run_orca_gate Disabled 1 >/dev/null 2>&1; then
    not_ok "gate accepted a PF load failure"
  else
    ok "gate fails closed when the PF configuration cannot load"
  fi
  require_contains "$launch_log" "disable system/com.stablyai.orca-server"
  require_contains "$launch_log" "kill SIGTERM system/com.stablyai.orca-server"
  [[ ! -e "$evidence_file" ]] && ok "gate removed stale evidence after a load failure" || \
    not_ok "gate kept evidence after a load failure"

  : >"$pfctl_log"
  : >"$launch_log"
  printf '%s\n' 'block drop in quick proto tcp from any to any port = 6768' >>"$live_rules"
  write_orca_gate_evidence
  if run_orca_gate Enabled >/dev/null 2>&1; then
    not_ok "gate accepted live rules that differ from the anchor"
  else
    ok "gate fails closed when live anchor rules differ"
  fi
  require_contains "$launch_log" "disable system/com.stablyai.orca-server"
  require_contains "$launch_log" "kill SIGTERM system/com.stablyai.orca-server"
  cp "$expected_rules" "$live_rules"

  : >"$pfctl_log"
  : >"$launch_log"
  mv "$anchor_file" "$anchor_file.bak"
  write_orca_gate_evidence
  if run_orca_gate Enabled >/dev/null 2>&1; then
    not_ok "gate accepted a missing anchor"
  else
    ok "gate fails closed when the anchor is missing"
  fi
  require_contains "$launch_log" "disable system/com.stablyai.orca-server"
  require_contains "$launch_log" "kill SIGTERM system/com.stablyai.orca-server"
  require_empty_file "$pfctl_log"
  mv "$anchor_file.bak" "$anchor_file"

  : >"$pfctl_log"
  : >"$launch_log"
  write_orca_gate_evidence
  if run_orca_gate Disabled 0 1 >/dev/null 2>&1; then
    not_ok "gate accepted a PF enable failure"
  else
    ok "gate fails closed when PF cannot be enabled"
  fi
  require_contains "$launch_log" "disable system/com.stablyai.orca-server"

  printf '%s\n' 'pass in quick proto tcp from any to any port 6768 flags S/SA keep state' 'anchor "com.stablyai.orca-server" all' >"$main_rules"
  : >"$pfctl_log"
  : >"$launch_log"
  write_orca_gate_evidence
  if run_orca_gate Enabled >/dev/null 2>&1; then
    not_ok "gate accepted an earlier quick rule before the Orca anchor"
  else
    ok "gate fails closed when an earlier quick rule can bypass the anchor"
  fi
  require_contains "$pfctl_log" "-sr"
  require_contains "$pfctl_log" "-f $pf_config"
  require_contains "$launch_log" "disable system/com.stablyai.orca-server"

  printf '%s\n' 'pass in quick proto tcp from any to any port 6768 flags S/SA keep state' 'anchor "com.stablyai.orca-server" all' >"$main_rules"
  printf '%s' 'Enabled' >"$pf_status_file"
  : >"$pfctl_log"
  : >"$launch_log"
  if (
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_LAUNCH_LOG="$launch_log" \
      ORCA_TEST_LIVE_RULES="$live_rules" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_MAIN_RULES="$main_rules" \
      ORCA_TEST_MAIN_RULES_AFTER="$main_rules_after" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      ORCA_TEST_PF_STATUS_FILE="$pf_status_file" \
      ORCA_TEST_LAUNCH_PRINT_RC="1" \
      bash "$gate_source"
  ) >/dev/null 2>&1; then
    ok "gate recovers the main ruleset after a reload"
  else
    not_ok "gate did not recover the main ruleset after a reload"
  fi
  require_contains "$launch_log" "kickstart system/com.stablyai.orca-server"

  printf '%s\n' '#!/bin/bash' 'exit 0' >"$stub_bin/exec-ok"
  chmod +x "$stub_bin/exec-ok"

  rm -f "$evidence_file"
  if (
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      bash "$server_source" "$stub_bin/exec-ok"
  ) >/dev/null 2>&1; then
    not_ok "Orca preflight started Orca without gate evidence"
  else
    ok "Orca preflight refuses to start Orca without gate evidence"
  fi

  printf '%s\n' "bootsession=OTHER-BOOT-SESSION" "anchor_sha256=$expected_hash" >"$evidence_file"
  if (
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      bash "$server_source" "$stub_bin/exec-ok"
  ) >/dev/null 2>&1; then
    not_ok "Orca preflight started Orca with evidence from another boot"
  else
    ok "Orca preflight refuses gate evidence from another boot"
  fi

  printf '%s\n' "bootsession=$boot_id" "anchor_sha256=$other_hash" >"$evidence_file"
  if (
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      bash "$server_source" "$stub_bin/exec-ok"
  ) >/dev/null 2>&1; then
    not_ok "Orca preflight started Orca with a stale anchor hash"
  else
    ok "Orca preflight refuses gate evidence with a stale anchor hash"
  fi

  printf '%s\n' "bootsession=$boot_id" "anchor_sha256=$expected_hash" >"$evidence_file"
  mv "$anchor_file" "$anchor_file.bak"
  if (
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      bash "$server_source" "$stub_bin/exec-ok"
  ) >/dev/null 2>&1; then
    not_ok "Orca preflight started Orca without the anchor"
  else
    ok "Orca preflight refuses to start Orca without the anchor"
  fi
  mv "$anchor_file.bak" "$anchor_file"

  if (
    ORCA_TEST_PFCTL_LOG="$pfctl_log" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      bash "$server_source" "$stub_bin/exec-ok"
  ) >/dev/null 2>&1; then
    ok "Orca preflight starts Orca with current-boot gate evidence"
  else
    not_ok "Orca preflight rejected current-boot gate evidence"
  fi

  printf '%s\n' '# preserve system PF rules' 'anchor "com.apple/*"' >"$pf_config"
  : >"$launch_log"
  : >"$install_cmd_log"
  if (
    PATH="$stub_bin:/usr/bin:/bin" \
      ORCA_TEST_LAUNCH_LOG="$launch_log" \
      ORCA_TEST_INSTALL_CMD_LOG="$install_cmd_log" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      bash "$install_script"
  ) >"$install_log" 2>&1; then
    not_ok "privileged install script continued after a pf.conf digest mismatch"
  else
    ok "privileged install script aborts on a pf.conf digest mismatch"
  fi
  require_empty_file "$install_cmd_log"
  require_empty_file "$launch_log"

  cp "$pf_config_source" "$pf_config"
  printf '%s\n' "bootsession=$boot_id" "anchor_sha256=$other_hash" >"$evidence_file"
  : >"$launch_log"
  : >"$install_cmd_log"
  if (
    PATH="$stub_bin:/usr/bin:/bin" \
      ORCA_TEST_LAUNCH_LOG="$launch_log" \
      ORCA_TEST_INSTALL_CMD_LOG="$install_cmd_log" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_EVIDENCE_FILE="$evidence_file" \
      ORCA_TEST_INSTALL_PUBLISH="0" \
      bash "$install_script"
  ) >"$install_log" 2>&1; then
    not_ok "privileged install script accepted evidence from the previous rollout"
  else
    ok "privileged install script requires fresh gate evidence"
  fi
  [[ ! -e "$evidence_file" ]] && ok "privileged install script removed old evidence" || \
    not_ok "privileged install script kept old evidence"

  : >"$launch_log"
  : >"$install_cmd_log"
  if (
    PATH="$stub_bin:/usr/bin:/bin" \
      ORCA_TEST_LAUNCH_LOG="$launch_log" \
      ORCA_TEST_INSTALL_CMD_LOG="$install_cmd_log" \
      ORCA_TEST_BOOT_ID="$boot_id" \
      ORCA_TEST_EXPECTED_RULES="$expected_rules" \
      ORCA_TEST_EVIDENCE_FILE="$evidence_file" \
      ORCA_TEST_INSTALL_PUBLISH="1" \
      bash "$install_script"
  ) >/dev/null 2>&1; then
    ok "privileged install script installs and starts the gate"
  else
    not_ok "privileged install script failed with a matching digest"
  fi
  require_contains "$install_cmd_log" "install -o root -g wheel -m 0755"
  require_contains "$install_cmd_log" "install -o root -g wheel -m 0644"
  require_contains "$launch_log" "disable system/com.stablyai.orca-server"
  require_contains "$launch_log" "enable system/com.stablyai.orca-firewall"
  require_contains "$launch_log" "bootstrap system"
  require_contains "$launch_log" "kickstart -k system/com.stablyai.orca-firewall"
  require_contains "$evidence_file" "bootsession=$boot_id"
  require_contains "$evidence_file" "anchor_sha256=$expected_hash"

  rm -rf -- "$fixture_root"
}

test_macos_orca_setup_order() {
  local fixture_root setup_log expected_log
  fixture_root="$(mktemp -d)"
  setup_log="$fixture_root/setup.log"
  expected_log="$fixture_root/expected.log"

  if (
    source "$REPO_DIR/apply.sh"
    agent_stack_platform() { printf '%s\n' Darwin; }
    install_orca_launch_daemon() { printf '%s\n' install-server >>"$setup_log"; }
    start_orca_firewall() { printf '%s\n' firewall >>"$setup_log"; }
    start_orca_launch_daemon() { printf '%s\n' verify-server >>"$setup_log"; }
    setup_orca
  ) >/dev/null 2>&1; then
    ok "macOS Orca setup runs its stages"
  else
    not_ok "macOS Orca setup order fixture failed"
  fi
  printf '%s\n' install-server firewall verify-server >"$expected_log"
  require_same_file "$expected_log" "$setup_log"

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
    configure_macos_bash_profile
    configure_macos_bash_profile
  ) >/dev/null 2>&1; then
    ok "macOS Bash profile setup applies twice"
  else
    not_ok "macOS Bash profile setup failed"
  fi
  require_contains "$profile" "export PRESERVE_ME=yes"
  require_text_count "$profile" "# >>> guisaliba/agents Bash aliases >>>" "1"
  require_text_count "$profile" "# <<< guisaliba/agents Bash aliases <<<" "1"
  require_contains "$profile" 'source "$HOME/.bash_aliases"'
  cp "$profile" "$first_profile"

  if (
    HOME="$fixture_home"
    PATH="/usr/bin:/bin"
    export HOME PATH
    source "$REPO_DIR/apply.sh"
    configure_macos_bash_profile
  ) >/dev/null 2>&1; then
    ok "Linux leaves the Bash profile unchanged"
  else
    not_ok "Linux Bash profile check failed"
  fi
  require_same_file "$first_profile" "$profile"

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
require_file "$REPO_DIR/orca/README.md"
require_contains "$REPO_DIR/README.md" "[orca/README.md](orca/README.md)"
require_contains "$REPO_DIR/orca/README.md" 'Port `6768` is for private Tailscale access only.'
require_contains "$REPO_DIR/orca/README.md" "sudo launchctl bootout system/com.stablyai.orca-server"
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
require_contains "$REPO_DIR/apply.sh" "sync_learn_plugin"
require_contains "$REPO_DIR/apply.sh" "PUPPETEER_SKIP_DOWNLOAD=true"
require_contains "$REPO_DIR/apply.sh" "$LEARN_REPOSITORY_URL_EXPECTED"
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
require_contains "$REPO_DIR/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."
require_text_count "$REPO_DIR/shell/opencode.bash" "$OPENCODE_SHELL_BLOCK_START" "1"
require_text_count "$REPO_DIR/shell/opencode.bash" "$OPENCODE_SHELL_BLOCK_END" "1"

# OpenCode merge fixture checks
printf '\n--- OpenCode Merge Fixtures ---\n'

test_opencode_json_merge
test_opencode_tui_json_merge
test_learn_plugin_sync

# ai-memory secret-file fixture checks
printf '\n--- ai-memory File Fixtures ---\n'

test_ai_memory_env_file

# Shared helper fixture checks
printf '\n--- Shared Helper Fixtures ---\n'

test_agent_stack_helpers
test_macos_platform_prerequisites
test_apply_scope

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
test_macos_orca_installation
test_macos_orca_launch_daemon
test_macos_orca_firewall
test_macos_orca_setup_order
test_ai_memory_user_service_installation
test_macos_ai_memory_launch_daemon
test_macos_bash_profile

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
require_command opencode
require_command ai-memory
require_command rtk
require_command plannotator
require_file "$HOME/.config/opencode/plugins/rtk.ts"

opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
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
  require_minimum_version opencode "$LEARN_MIN_OPENCODE_VERSION"
) >/dev/null 2>&1; then
  ok "opencode is installed at version $LEARN_MIN_OPENCODE_VERSION or newer"
else
  not_ok "opencode is missing, is older than $LEARN_MIN_OPENCODE_VERSION, or is unreadable"
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
require_contains "$HOME/.config/opencode/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."
require_same_file "$REPO_DIR/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
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
require_json_value "$HOME/.config/opencode/opencode.json" "model" "openai/gpt-5.6-sol-fast"
require_json_value "$HOME/.config/opencode/opencode.json" "default_agent" "build"
require_json_value "$HOME/.config/opencode/opencode.json" "agent.plan.model" "openai/gpt-5.6-sol-fast"
selected_profile_log="$(mktemp)"
if selected_profile="$(
  source "$REPO_DIR/apply.sh"
  ai_memory_selected_profile 2>"$selected_profile_log"
)"; then
  ok "ai-memory profile selection is supported: $selected_profile"
  profile_spec="$(
    source "$REPO_DIR/apply.sh"
    ai_memory_profile_spec "$selected_profile"
  )"
  IFS='|' read -r expected_provider expected_model credential expected_subagent_model <<<"$profile_spec"
  require_json_value "$HOME/.config/opencode/opencode.json" "agent.general.model" "$expected_subagent_model"
  require_json_value "$HOME/.config/opencode/opencode.json" "agent.explore.model" "$expected_subagent_model"
else
  not_ok "ai-memory profile selection is unsupported or unreadable"
  sed 's/^/  /' "$selected_profile_log" >&2
fi
rm -f "$selected_profile_log"

model_catalog="$(opencode models 2>/dev/null || true)"
if [[ -n "$model_catalog" ]]; then
  model_catalog_lines=$'\n'"$model_catalog"$'\n'
  for profile_name in $(profile_names); do
    catalog_model="$(profile_field "$profile_name" subagent)"
    if [[ "$model_catalog_lines" == *$'\n'"$catalog_model"$'\n'* ]]; then
      ok "opencode model catalog contains $catalog_model"
    else
      not_ok "opencode model catalog does not contain $catalog_model for profile $profile_name"
    fi
  done
else
  not_ok "opencode models returned no catalog"
fi
require_json_array_count "$HOME/.config/opencode/opencode.json" "instructions" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" "1"
require_json_array_count "$HOME/.config/opencode/opencode.json" "plugin" "$LEARN_PLUGIN_SPEC" "1"
require_json_array_count "$HOME/.config/opencode/opencode.json" "plugin" "$LEARN_LEGACY_PLUGIN_BASE" "0"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.ai-memory" "$AI_MEMORY_MCP_EXPECTED_JSON"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.type" "remote"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.url" "https://api.githubcopilot.com/mcp/"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.github.enabled" "true"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.github.oauth" "false"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.headers.Authorization" "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}"
require_json_value "$HOME/.config/opencode/opencode.json" "mcp.github.headers.X-MCP-Toolsets" "context,repos,issues,pull_requests,actions"
require_json_literal "$HOME/.config/opencode/opencode.json" "mcp.github" "$GITHUB_MCP_EXPECTED_JSON"

require_contains "$HOME/.config/opencode/opencode.json" "@plannotator/opencode@latest"
require_file "$HOME/.config/opencode/tui.json"
require_json "$HOME/.config/opencode/tui.json"
require_json_value "$HOME/.config/opencode/tui.json" "theme" "$OPENCODE_TUI_THEME_EXPECTED"
for theme_file in "${tracked_theme_files[@]}"; do
  require_same_file "$theme_file" "$HOME/.config/opencode/themes/${theme_file##*/}"
done
require_json_array_count "$HOME/.config/opencode/tui.json" "plugin" "$LEARN_PLUGIN_SPEC" "1"
require_json_array_count "$HOME/.config/opencode/tui.json" "plugin" "$LEARN_LEGACY_PLUGIN_BASE" "0"

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
case "$(uname -s)" in
  Linux)
    require_file "$AI_MEMORY_USER_SERVICE_FILE"
    require_file_mode "$AI_MEMORY_USER_SERVICE_FILE" "644"
    require_contains "$AI_MEMORY_USER_SERVICE_FILE" "# Managed by guisaliba/agents apply.sh."
    require_contains "$AI_MEMORY_USER_SERVICE_FILE" "--data-dir %h/.local/share/ai-memory"
    systemctl --user is-enabled --quiet ai-memory.service >/dev/null 2>&1 && \
      ok "ai-memory user service is enabled" || not_ok "ai-memory user service is not enabled"
    systemctl --user is-active --quiet ai-memory.service >/dev/null 2>&1 && \
      ok "ai-memory user service is active" || not_ok "ai-memory user service is not active"
    require_ai_memory_status
    ;;
  Darwin)
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

if [[ "$(uname -s)" == Darwin ]]; then
  printf '\n--- Orca Remote Server ---\n'

  require_command orca
  orca --version >/dev/null 2>&1 && ok "Orca version runs" || not_ok "Orca version failed"
  require_file "$ORCA_LAUNCH_DAEMON_SOURCE_FILE"
  require_file_mode "$ORCA_LAUNCH_DAEMON_SOURCE_FILE" "600"
  require_file "$ORCA_LAUNCH_DAEMON_FILE"
  require_file_mode "$ORCA_LAUNCH_DAEMON_FILE" "644"
  require_file "$ORCA_FIREWALL_SCRIPT_SOURCE_FILE"
  require_file_mode "$ORCA_FIREWALL_SCRIPT_SOURCE_FILE" "600"
  require_file "$ORCA_FIREWALL_SCRIPT_FILE"
  require_file_mode "$ORCA_FIREWALL_SCRIPT_FILE" "755"
  require_same_file "$ORCA_FIREWALL_SCRIPT_SOURCE_FILE" "$ORCA_FIREWALL_SCRIPT_FILE"
  require_file "$ORCA_SERVER_SCRIPT_SOURCE_FILE"
  require_file_mode "$ORCA_SERVER_SCRIPT_SOURCE_FILE" "600"
  require_file "$ORCA_SERVER_SCRIPT_FILE"
  require_file_mode "$ORCA_SERVER_SCRIPT_FILE" "755"
  require_same_file "$ORCA_SERVER_SCRIPT_SOURCE_FILE" "$ORCA_SERVER_SCRIPT_FILE"
  require_file "$ORCA_INSTALL_SCRIPT_FILE"
  require_file_mode "$ORCA_INSTALL_SCRIPT_FILE" "700"
  require_file_mode "$HOME/Library/Logs/orca-server" "700"
  require_file_mode "$HOME/Library/Logs/orca-server/stdout.log" "600"
  require_file_mode "$HOME/Library/Logs/orca-server/stderr.log" "600"
  if [[ "$(stat -f '%Su:%Sg' "$ORCA_LAUNCH_DAEMON_FILE" 2>/dev/null || true)" == "root:wheel" ]]; then
    ok "Orca LaunchDaemon is owned by root:wheel"
  else
    not_ok "Orca LaunchDaemon is not owned by root:wheel"
  fi
  if (
    source "$REPO_DIR/apply.sh"
    orca_launch_daemon_matches
  ) >/dev/null 2>&1; then
    ok "installed Orca LaunchDaemon matches the managed contract"
  else
    not_ok "installed Orca LaunchDaemon does not match the managed contract"
  fi
  if launchctl print "system/$ORCA_LAUNCH_DAEMON_LABEL" >/dev/null 2>&1; then
    ok "Orca LaunchDaemon is active"
  else
    not_ok "Orca LaunchDaemon is not active"
  fi
  if lsof -nP -iTCP:6768 -sTCP:LISTEN >/dev/null 2>&1; then
    ok "Orca listens on TCP port 6768"
  else
    not_ok "Orca does not listen on TCP port 6768"
  fi

  require_file "$ORCA_PF_CONFIG_SOURCE_FILE"
  require_file_mode "$ORCA_PF_CONFIG_SOURCE_FILE" "600"
  if /sbin/pfctl -nf "$ORCA_PF_CONFIG_SOURCE_FILE" >/dev/null 2>&1; then
    ok "generated Orca PF configuration parses"
  else
    not_ok "generated Orca PF configuration is invalid"
  fi
  require_file "$ORCA_PF_CONFIG_ROLLBACK_FILE"
  require_file_mode "$ORCA_PF_CONFIG_ROLLBACK_FILE" "600"
  require_file "$ORCA_PF_CONFIG_DIGEST_FILE"
  require_file_mode "$ORCA_PF_CONFIG_DIGEST_FILE" "600"
  require_file "$ORCA_PF_ANCHOR_SOURCE_FILE"
  require_file_mode "$ORCA_PF_ANCHOR_SOURCE_FILE" "600"
  require_file "$ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE"
  require_file_mode "$ORCA_FIREWALL_LAUNCH_DAEMON_SOURCE_FILE" "600"
  require_same_file "$ORCA_PF_CONFIG_SOURCE_FILE" "$ORCA_PF_CONFIG_FILE"
  require_same_file "$ORCA_PF_ANCHOR_SOURCE_FILE" "$ORCA_PF_ANCHOR_FILE"
  require_file_mode "$ORCA_PF_CONFIG_FILE" "644"
  require_file_mode "$ORCA_PF_ANCHOR_FILE" "644"
  require_file_mode "$ORCA_FIREWALL_LAUNCH_DAEMON_FILE" "644"
  require_file "$ORCA_GATE_EVIDENCE_FILE"
  require_file_mode "$ORCA_GATE_EVIDENCE_FILE" "644"
  for system_file in \
    "$ORCA_PF_CONFIG_FILE" \
    "$ORCA_PF_ANCHOR_FILE" \
    "$ORCA_FIREWALL_LAUNCH_DAEMON_FILE" \
    "$ORCA_FIREWALL_SCRIPT_FILE" \
    "$ORCA_SERVER_SCRIPT_FILE" \
    "$ORCA_GATE_EVIDENCE_FILE"
  do
    if [[ "$(stat -f '%Su:%Sg' "$system_file" 2>/dev/null || true)" == "root:wheel" ]]; then
      ok "Orca firewall file is owned by root:wheel: $system_file"
    else
      not_ok "Orca firewall file is not owned by root:wheel: $system_file"
    fi
  done
  if (
    source "$REPO_DIR/apply.sh"
    orca_firewall_daemon_matches
  ) >/dev/null 2>&1; then
    ok "installed Orca firewall gate LaunchDaemon matches the managed contract"
  else
    not_ok "installed Orca firewall gate LaunchDaemon does not match the managed contract"
  fi
  if launchctl print "system/$ORCA_FIREWALL_LABEL" >/dev/null 2>&1; then
    ok "Orca firewall gate LaunchDaemon is loaded"
  else
    not_ok "Orca firewall gate LaunchDaemon is not loaded"
  fi
  require_file_mode "$HOME/Library/Logs/orca-server/firewall-stdout.log" "600"
  require_file_mode "$HOME/Library/Logs/orca-server/firewall-stderr.log" "600"
  if python3 - \
    "$ORCA_GATE_EVIDENCE_FILE" \
    "$ORCA_PF_CONFIG_DIGEST_FILE" \
    "$ORCA_PF_CONFIG_FILE" \
    "$ORCA_PF_ANCHOR_SOURCE_FILE" <<'PY'
import hashlib
import subprocess
import sys
from pathlib import Path

evidence = Path(sys.argv[1])
digest_file = Path(sys.argv[2])
pf_config = Path(sys.argv[3])
anchor_source = Path(sys.argv[4])

recorded = {}
for line in evidence.read_text(encoding="utf-8").splitlines():
    key, separator, value = line.partition("=")
    if separator:
        recorded[key] = value

boot = subprocess.run(
    ["/usr/sbin/sysctl", "-n", "kern.bootsessionuuid"],
    capture_output=True,
    text=True,
    check=True,
).stdout.strip()
rules = subprocess.run(
    ["/sbin/pfctl", "-a", "com.stablyai.orca-server", "-nvf", str(anchor_source)],
    capture_output=True,
    text=True,
    check=True,
).stdout
anchor_hash = hashlib.sha256(rules.encode()).hexdigest()
pf_config_hash = hashlib.sha256(pf_config.read_bytes()).hexdigest()

raise SystemExit(
    0
    if recorded.get("bootsession") == boot
    and recorded.get("anchor_sha256") == anchor_hash
    and digest_file.read_text(encoding="utf-8").strip() == pf_config_hash
    else 1
)
PY
  then
    ok "Orca firewall gate evidence is current for this boot and matches the live anchor"
  else
    not_ok "Orca firewall gate evidence is stale, mismatched, or not bound to this boot"
  fi
fi

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
