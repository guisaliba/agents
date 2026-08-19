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

failures=0
GITHUB_MCP_TOKEN_FILE="$HOME/.config/opencode/secrets/github-mcp-pat"
GITHUB_MCP_EXPECTED_JSON='{"type":"remote","url":"https://api.githubcopilot.com/mcp/","enabled":true,"oauth":false,"headers":{"Authorization":"Bearer {file:~/.config/opencode/secrets/github-mcp-pat}","X-MCP-Toolsets":"context,repos,issues,pull_requests,actions"}}'
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
AI_MEMORY_INSTRUCTIONS_FILE="$HOME/.config/opencode/ai-memory.md"
AI_MEMORY_INSTRUCTIONS_REFERENCE="~/.config/opencode/ai-memory.md"
AI_MEMORY_MCP_EXPECTED_JSON='{"type":"remote","url":"http://127.0.0.1:49374/mcp","enabled":true}'
AI_MEMORY_MIN_VERSION="1.28.0"
AI_JAIL_MIN_VERSION="1.18.1"
AI_MEMORY_LLM_PROFILE_EXPECTED="opencode-go-deepseek"
AI_MEMORY_LLM_PROVIDER_EXPECTED="opencode"
AI_MEMORY_LLM_MODEL_EXPECTED="deepseek-v4-flash"
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

env_assignment_has_nonempty_value() {
  local path="$1"
  local name="$2"
  if python3 - "$path" "$name" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
name = sys.argv[2]
pattern = re.compile(rf"^\s*{re.escape(name)}\s*=\s*(.*?)\s*$")
value = ""

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

raise SystemExit(0 if value.strip() else 1)
PY
  then
    return 0
  else
    return 1
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
    "plugin": "user/plugin",
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

# Repo structure checks
printf '\n--- Repo Structure ---\n'

require_file "$DOTFILES_DIR/agents/AGENTS.md"
require_file "$DOTFILES_DIR/agents/apply.sh"
require_file "$DOTFILES_DIR/agents/test.sh"
require_file "$DOTFILES_DIR/agents/opencode/README.md"
require_file "$DOTFILES_DIR/agents/skills/README.md"
require_file "$DOTFILES_DIR/bash/.bash_aliases"
require_executable "$DOTFILES_DIR/agents/apply.sh"
require_executable "$DOTFILES_DIR/agents/test.sh"
require_contains "$DOTFILES_DIR/agents/apply.sh" 'install_skill "https://github.com/almendili/skills" "architecture-map"'
if [[ ! -e "$DOTFILES_DIR/agents/skills/architecture-map" ]]; then
  ok "architecture-map is not locally vendored"
else
  not_ok "architecture-map must be installed from upstream, not locally vendored"
fi
require_contains "$DOTFILES_DIR/agents/AGENTS.md" "When you are the primary agent, you are the final owner of delegated work."
require_text_count "$DOTFILES_DIR/bash/.bash_aliases" "$OPENCODE_SHELL_BLOCK_START" "1"
require_text_count "$DOTFILES_DIR/bash/.bash_aliases" "$OPENCODE_SHELL_BLOCK_END" "1"

# OpenCode merge fixture checks
printf '\n--- OpenCode Merge Fixtures ---\n'

test_opencode_json_merge

# ai-memory secret-file fixture checks
printf '\n--- ai-memory File Fixtures ---\n'

test_ai_memory_env_file

# Bash command override fixture checks
printf '\n--- OpenCode Bash Override Fixtures ---\n'

test_opencode_shell_override

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
require_command ai-jail
require_command rtk
require_command plannotator
require_file "$HOME/.config/opencode/plugins/rtk.ts"

opencode --help >/dev/null 2>&1 && ok "opencode help runs" || not_ok "opencode help failed"
ai-memory --help >/dev/null 2>&1 && ok "ai-memory help runs" || not_ok "ai-memory help failed"
ai-jail --help >/dev/null 2>&1 && ok "ai-jail help runs" || not_ok "ai-jail help failed"
plannotator --help >/dev/null 2>&1 && ok "plannotator help runs" || not_ok "plannotator help failed"

if (
  source "$DOTFILES_DIR/agents/apply.sh"
  require_minimum_version ai-memory "$AI_MEMORY_MIN_VERSION"
) >/dev/null 2>&1; then
  ok "ai-memory version is supported"
else
  not_ok "ai-memory version is older than $AI_MEMORY_MIN_VERSION or unreadable"
fi

if (
  source "$DOTFILES_DIR/agents/apply.sh"
  require_minimum_version ai-jail "$AI_JAIL_MIN_VERSION"
) >/dev/null 2>&1; then
  ok "ai-jail version is supported"
else
  not_ok "ai-jail version is older than $AI_JAIL_MIN_VERSION or unreadable"
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

systemctl --user is-enabled --quiet ai-memory.service >/dev/null 2>&1 && \
  ok "ai-memory user service is enabled" || not_ok "ai-memory user service is not enabled"
systemctl --user is-active --quiet ai-memory.service >/dev/null 2>&1 && \
  ok "ai-memory user service is active" || not_ok "ai-memory user service is not active"
require_ai_memory_status

# Required skills
printf '\n--- Skills ---\n'

for skill in \
  caveman \
  find-skills \
  architecture-map \
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
  ai-memory-retrieval \
  ai-memory-handoff \
  ai-memory-durable-pages \
  ai-memory-learning-maintenance \
  ai-memory-routing-install \
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

for skill in find-skills architecture-map auto-pr-review; do
  require_file "$HOME/.agents/skills/$skill/SKILL.md"
done
require_contains "$HOME/.agents/skills/architecture-map/SKILL.md" "name: architecture-map"

# Result
printf '\n'
if [[ "$failures" -gt 0 ]]; then
  printf 'agent stack tests failed: %s\n' "$failures" >&2
  exit 1
fi

printf 'agent stack tests passed\n'
