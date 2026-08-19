#!/usr/bin/env bash
set -Eeuo pipefail

# apply.sh
#
# Deterministic OpenCode setup script.
# Installs OpenCode, ai-memory, ai-jail, RTK, Plannotator, and required skills.
# Installs/updates skills live on every run.
#
# Usage:
#   ./agents/apply.sh
#
# Prerequisites: curl, git, npm, npx, python3, systemctl.
# AUR package installation also needs yay when ai-memory or ai-jail is absent.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
RTK_VERSION="${RTK_VERSION:-v0.38.0}"
GITHUB_MCP_TOKEN_FILE="$HOME/.config/opencode/secrets/github-mcp-pat"
GITHUB_MCP_TOKEN_REFERENCE="~/.config/opencode/secrets/github-mcp-pat"
AI_MEMORY_AUR_PACKAGE="${AI_MEMORY_AUR_PACKAGE:-ai-memory-bin}"
AI_JAIL_AUR_PACKAGE="${AI_JAIL_AUR_PACKAGE:-ai-jail-bin}"
AI_MEMORY_MIN_VERSION="${AI_MEMORY_MIN_VERSION:-1.28.0}"
AI_JAIL_MIN_VERSION="${AI_JAIL_MIN_VERSION:-1.18.1}"
AI_MEMORY_DATA_DIR="$HOME/.local/share/ai-memory"
AI_MEMORY_AUTH_FILE="$AI_MEMORY_DATA_DIR/auth.json"
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
AI_MEMORY_LOOPBACK_SERVER_URL="http://127.0.0.1:49374"
AI_MEMORY_INSTRUCTIONS_FILE="$HOME/.config/opencode/ai-memory.md"
AI_MEMORY_INSTRUCTIONS_REFERENCE="~/.config/opencode/ai-memory.md"
AI_MEMORY_DEFAULT_LLM_PROFILE="opencode-go-deepseek"
BASH_ALIASES_SOURCE="$DOTFILES_DIR/bash/.bash_aliases"
BASH_ALIASES_FILE="$HOME/.bash_aliases"
OPENCODE_SHELL_BLOCK_START="# >>> dotfiles OpenCode ai-memory wrapper >>>"
OPENCODE_SHELL_BLOCK_END="# <<< dotfiles OpenCode ai-memory wrapper <<<"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
  log "Checking prerequisites"
  local missing=()
  for cmd in bash curl git npm npx python3 systemctl; do
    if ! have "$cmd"; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing prerequisites: ${missing[*]}. Install them before running this script."
  fi
  python3 -c 'import tomllib' >/dev/null 2>&1 || \
    die "Python 3.11 or newer is required for safe ai-memory TOML validation."
  log "All prerequisites present"
}

install_aur_command() {
  local command_name="$1"
  local package_name="$2"

  if have "$command_name"; then
    log "$command_name already installed, skipping"
    return
  fi

  have yay || die "$command_name is missing. Install $package_name with an AUR helper, or put a supported native $command_name binary on PATH before running apply."

  log "Installing $command_name from the AUR package $package_name"
  yay -S --needed --noconfirm "$package_name" || die "$package_name installation failed"
  have "$command_name" || die "$package_name did not put $command_name on PATH"
}

require_minimum_version() {
  local command_name="$1"
  local minimum="$2"
  local version_output
  version_output="$("$command_name" --version 2>/dev/null)" || die "Could not read $command_name version"

  if ! python3 - "$command_name" "$minimum" "$version_output" <<'PY'
import re
import sys

name = sys.argv[1]
minimum_text = sys.argv[2]
output = sys.argv[3]
match = re.search(r"(\d+)\.(\d+)\.(\d+)", output)
if not match:
    raise SystemExit(f"ERROR: Could not parse {name} version from: {output!r}")

actual = tuple(int(part) for part in match.groups())
minimum = tuple(int(part) for part in minimum_text.split("."))
if actual < minimum:
    raise SystemExit(
        f"ERROR: {name} {'.'.join(map(str, actual))} is too old; "
        f"version {minimum_text} or newer is required."
    )
PY
  then
    die "$command_name version check failed"
  fi
}

install_ai_memory() {
  install_aur_command ai-memory "$AI_MEMORY_AUR_PACKAGE"
  require_minimum_version ai-memory "$AI_MEMORY_MIN_VERSION"
}

install_ai_jail() {
  install_aur_command ai-jail "$AI_JAIL_AUR_PACKAGE"
  require_minimum_version ai-jail "$AI_JAIL_MIN_VERSION"
}

verify_ai_memory_no_static_auth_files() {
  python3 - "$AI_MEMORY_CONFIG_FILE" "$AI_MEMORY_ENV_FILE" <<'PY'
import re
import sys
import tomllib
from pathlib import Path

config_path = Path(sys.argv[1])
env_path = Path(sys.argv[2])

if config_path.exists():
    try:
        with config_path.open("rb") as config_file:
            config = tomllib.load(config_file)
    except (OSError, tomllib.TOMLDecodeError) as exc:
        raise SystemExit(f"ERROR: Cannot read valid ai-memory config at {config_path}: {exc}")

    auth = config.get("auth", {})
    if not isinstance(auth, dict):
        raise SystemExit(f"ERROR: Expected [auth] to be a table in {config_path}")
    for key in ("bearer_token", "actor_proxy_bearer_token"):
        value = auth.get(key)
        if value is not None and (not isinstance(value, str) or value.strip()):
            raise SystemExit(
                f"ERROR: {config_path} sets [auth].{key}; "
                "this loopback integration must stay unauthenticated"
            )

if env_path.exists():
    try:
        lines = env_path.read_text(encoding="utf-8").splitlines()
    except OSError as exc:
        raise SystemExit(f"ERROR: Cannot read ai-memory environment file at {env_path}: {exc}")

    for line in lines:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        match = re.match(
            r"^\s*(AI_MEMORY_AUTH_TOKEN|AI_MEMORY_AUTH__BEARER_TOKEN|"
            r"AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN)\s*=\s*(.*?)\s*$",
            line,
        )
        if match is None:
            continue
        name = match.group(1)
        value = match.group(2)
        if len(value) >= 2 and value[0] == value[-1] and value[0] in "\"'":
            value = value[1:-1]
        if value.strip():
            raise SystemExit(
                f"ERROR: {env_path} sets {name}; "
                "this loopback integration must stay unauthenticated"
            )
PY
}

verify_ai_memory_unauthenticated_loopback() {
  local auth_variable
  log "Verifying the unauthenticated ai-memory loopback policy"

  for auth_variable in \
    AI_MEMORY_AUTH_TOKEN \
    AI_MEMORY_AUTH__BEARER_TOKEN \
    AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN
  do
    [[ -z "${!auth_variable:-}" ]] || \
      die "$auth_variable is set in the current shell. Unset it for this managed loopback design."
  done

  verify_ai_memory_no_static_auth_files || \
    die "Remove static ai-memory bearer authentication before running apply."

  if ! systemctl --user show-environment 2>/dev/null | python3 -c '
import sys

auth_names = {
    "AI_MEMORY_AUTH_TOKEN",
    "AI_MEMORY_AUTH__BEARER_TOKEN",
    "AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN",
}
for line in sys.stdin:
    name, separator, value = line.rstrip("\n").partition("=")
    if separator and name in auth_names and value.strip():
        raise SystemExit(1)
'; then
    die "Could not verify a token-free systemd user environment. Unset AI_MEMORY_AUTH_TOKEN, AI_MEMORY_AUTH__BEARER_TOKEN, and AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN with systemctl --user unset-environment, and confirm that the user manager is running."
  fi
}

install_opencode() {
  if have opencode; then
    log "OpenCode already installed, skipping"
    return
  fi

  log "Installing OpenCode"
  curl -fsSL https://opencode.ai/install | bash || die "OpenCode install failed"

  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  have opencode || die "OpenCode install did not put opencode on PATH"
}

merge_opencode_shell_override() {
  log "Making interactive Bash OpenCode starts use ai-memory managed workstreams"

  python3 - \
    "$BASH_ALIASES_SOURCE" \
    "$BASH_ALIASES_FILE" \
    "$OPENCODE_SHELL_BLOCK_START" \
    "$OPENCODE_SHELL_BLOCK_END" <<'PY'
import os
import stat
import sys
import tempfile
from pathlib import Path

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
start_marker = sys.argv[3]
end_marker = sys.argv[4]


def locate_block(lines, path, allow_absent):
    starts = [index for index, line in enumerate(lines) if line == start_marker]
    ends = [index for index, line in enumerate(lines) if line == end_marker]
    if not starts and not ends and allow_absent:
        return None
    if len(starts) != 1 or len(ends) != 1 or ends[0] <= starts[0]:
        raise SystemExit(
            f"ERROR: Expected one balanced OpenCode wrapper block in {path}; "
            "file was not changed"
        )
    return starts[0], ends[0]


try:
    source_lines = source_path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read Bash alias source {source_path}: {exc}")

source_bounds = locate_block(source_lines, source_path, allow_absent=False)
source_start, source_end = source_bounds
canonical_block = source_lines[source_start : source_end + 1]

if target_path.is_symlink():
    try:
        same_source = target_path.resolve(strict=True) == source_path.resolve(strict=True)
    except OSError as exc:
        raise SystemExit(f"ERROR: Cannot resolve Bash alias target {target_path}: {exc}")
    if same_source:
        raise SystemExit(0)
    raise SystemExit(
        f"ERROR: Bash alias target must not be an unrelated symlink: {target_path}"
    )

if target_path.exists() and not target_path.is_file():
    raise SystemExit(f"ERROR: Bash alias target must be a regular file: {target_path}")

if target_path.exists():
    try:
        target_text = target_path.read_text(encoding="utf-8")
        target_mode = stat.S_IMODE(target_path.stat().st_mode)
    except OSError as exc:
        raise SystemExit(f"ERROR: Cannot read Bash alias target {target_path}: {exc}")
    target_lines = target_text.splitlines()
else:
    target_text = ""
    target_mode = 0o644
    target_lines = []

target_bounds = locate_block(target_lines, target_path, allow_absent=True)
if target_bounds is None:
    kept_lines = target_lines
else:
    target_start, target_end = target_bounds
    kept_lines = target_lines[:target_start] + target_lines[target_end + 1 :]

while kept_lines and not kept_lines[-1].strip():
    kept_lines.pop()
if kept_lines:
    kept_lines.append("")
kept_lines.extend(canonical_block)
content = "\n".join(kept_lines) + "\n"

if target_path.exists() and content == target_text:
    raise SystemExit(0)

target_path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
descriptor, temporary_name = tempfile.mkstemp(prefix=".bash_aliases.", dir=target_path.parent)
try:
    os.fchmod(descriptor, target_mode)
    with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
        temporary_file.write(content)
        temporary_file.flush()
        os.fsync(temporary_file.fileno())
    os.replace(temporary_name, target_path)
except BaseException:
    try:
        os.close(descriptor)
    except OSError:
        pass
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
    raise
PY
}

copy_agents_md() {
  log "Copying canonical AGENTS.md to OpenCode global config"

  local src="$DOTFILES_DIR/agents/AGENTS.md"
  [[ -f "$src" ]] || die "Missing canonical agent instructions: $src"

  mkdir -p "$HOME/.config/opencode"
  cp "$src" "$HOME/.config/opencode/AGENTS.md"
}

ensure_github_mcp_token_file() {
  log "Preparing the machine-local GitHub MCP token file"

  python3 - "$GITHUB_MCP_TOKEN_FILE" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
path.parent.chmod(0o700)

if path.is_symlink():
    raise SystemExit(f"ERROR: GitHub MCP token path must not be a symlink: {path}")
if path.exists() and not path.is_file():
    raise SystemExit(f"ERROR: GitHub MCP token path must be a regular file: {path}")
if not path.exists():
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)

path.chmod(0o600)
PY
}

native_scout_available() {
  local clean_home output
  clean_home="$(mktemp -d)"

  if output="$(
    HOME="$clean_home" \
      OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
      opencode agent list --pure 2>/dev/null
  )" && [[ "$output" == *$'\nscout (subagent)\n'* ]]; then
    rm -rf "$clean_home"
    return 0
  fi

  rm -rf "$clean_home"
  return 1
}

merge_opencode_json() {
  log "Merging OpenCode opencode.json"

  local config="$HOME/.config/opencode/opencode.json"
  local manage_scout=false
  mkdir -p "$(dirname "$config")"

  if native_scout_available; then
    manage_scout=true
    log "Native Scout subagent available; applying its model override"
  else
    log "Native Scout subagent unavailable; leaving Scout unmanaged"
  fi

  python3 - "$config" "$manage_scout" "$GITHUB_MCP_TOKEN_REFERENCE" "$AI_MEMORY_INSTRUCTIONS_REFERENCE" <<'PY'
import json
import os
import sys

path = sys.argv[1]
manage_scout = sys.argv[2] == "true"
github_mcp_token_reference = sys.argv[3]
ai_memory_instructions_reference = sys.argv[4]
data = {}

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"ERROR: Invalid JSON in {path} at line {exc.lineno}, "
            f"column {exc.colno}: {exc.msg}. File was not changed."
        )

if not isinstance(data, dict):
    raise SystemExit(
        f"ERROR: Expected a JSON object in {path}, found "
        f"{type(data).__name__}. File was not changed."
    )

data.setdefault("$schema", "https://opencode.ai/config.json")

sol_model = "openai/gpt-5.6-sol"
deepseek_model = "opencode-go/deepseek-v4-flash"
data["model"] = sol_model
data["default_agent"] = "build"

agents = data.get("agent", {})
if not isinstance(agents, dict):
    raise SystemExit(
        f"ERROR: Expected 'agent' to be an object in {path}. File was not changed."
    )

managed_models = {
    "plan": sol_model,
    "general": deepseek_model,
    "explore": deepseek_model,
}
if manage_scout:
    managed_models["scout"] = deepseek_model

for name, model in managed_models.items():
    config = agents.get(name, {})
    if not isinstance(config, dict):
        raise SystemExit(
            f"ERROR: Expected 'agent.{name}' to be an object in {path}. "
            "File was not changed."
        )
    config["model"] = model
    agents[name] = config

if not manage_scout and "scout" in agents:
    scout = agents["scout"]
    if not isinstance(scout, dict):
        raise SystemExit(
            f"ERROR: Expected 'agent.scout' to be an object in {path}. "
            "File was not changed."
        )
    if scout.get("model") == deepseek_model:
        scout.pop("model")
        if not scout:
            agents.pop("scout")

data["agent"] = agents

instructions = data.get("instructions", [])
if not isinstance(instructions, list):
    raise SystemExit(
        f"ERROR: Expected 'instructions' to be an array in {path}. "
        "File was not changed."
    )
instructions = [
    item for item in instructions if item != ai_memory_instructions_reference
]
instructions.append(ai_memory_instructions_reference)
data["instructions"] = instructions

plugin = "@plannotator/opencode@latest"
plugins = data.get("plugin", [])
if isinstance(plugins, str):
    plugins = [plugins]
elif isinstance(plugins, list):
    plugins = list(plugins)
else:
    raise SystemExit(
        f"ERROR: Expected 'plugin' to be an array or string in {path}. "
        "File was not changed."
    )
if plugin not in plugins:
    plugins.append(plugin)
data["plugin"] = plugins

cloudflare_mcps = {
    "cloudflare-api": "https://mcp.cloudflare.com/mcp",
    "cloudflare-docs": "https://docs.mcp.cloudflare.com/mcp",
    "cloudflare-bindings": "https://bindings.mcp.cloudflare.com/mcp",
    "cloudflare-builds": "https://builds.mcp.cloudflare.com/mcp",
    "cloudflare-observability": "https://observability.mcp.cloudflare.com/mcp",
}
remote_mcps = {
    **cloudflare_mcps,
    "linear": "https://mcp.linear.app/mcp",
}
mcp = data.get("mcp", {})
if not isinstance(mcp, dict):
    raise SystemExit(
        f"ERROR: Expected 'mcp' to be an object in {path}. File was not changed."
    )
for name, url in remote_mcps.items():
    existing = mcp.get(name)
    if isinstance(existing, dict) and existing.get("url") == url:
        continue
    mcp[name] = {"type": "remote", "url": url, "enabled": True}
mcp["ai-memory"] = {
    "type": "remote",
    "url": "http://127.0.0.1:49374/mcp",
    "enabled": True,
}
mcp["github"] = {
    "type": "remote",
    "url": "https://api.githubcopilot.com/mcp/",
    "enabled": True,
    "oauth": False,
    "headers": {
        "Authorization": f"Bearer {{file:{github_mcp_token_reference}}}",
        "X-MCP-Toolsets": "context,repos,issues,pull_requests,actions",
    },
}
data["mcp"] = mcp

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

setup_opencode() {
  copy_agents_md
  ensure_github_mcp_token_file
  merge_opencode_json
}

ensure_ai_memory_env_file() {
  log "Preparing the machine-local ai-memory environment file"

  python3 - "$AI_MEMORY_ENV_FILE" <<'PY'
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
path.parent.chmod(0o700)

if path.is_symlink():
    raise SystemExit(f"ERROR: ai-memory environment path must not be a symlink: {path}")
if path.exists() and not path.is_file():
    raise SystemExit(f"ERROR: ai-memory environment path must be a regular file: {path}")
if not path.exists():
    descriptor = os.open(path, os.O_CREAT | os.O_EXCL | os.O_WRONLY, 0o600)
    os.close(descriptor)

path.chmod(0o600)
PY
}

ai_memory_env_value() {
  local name="$1"

  python3 - "$AI_MEMORY_ENV_FILE" "$name" <<'PY'
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

ai_memory_env_has_nonempty_value() {
  local name="$1"
  local value

  value="$(ai_memory_env_value "$name" 2>/dev/null)" || return 1
  [[ -n "$value" ]]
}

ai_memory_openai_oauth_state() {
  python3 - "$AI_MEMORY_AUTH_FILE" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
if path.is_symlink():
    raise SystemExit(f"ERROR: ai-memory auth path must not be a symlink: {path}")
if not path.exists():
    print("missing")
    raise SystemExit(0)
if not path.is_file():
    raise SystemExit(f"ERROR: ai-memory auth path must be a regular file: {path}")

try:
    root = json.loads(path.read_text(encoding="utf-8"))
except (OSError, json.JSONDecodeError) as exc:
    raise SystemExit(f"ERROR: Cannot read valid ai-memory auth JSON at {path}: {exc}")

if not isinstance(root, dict):
    raise SystemExit(f"ERROR: ai-memory auth file must contain a JSON object: {path}")
if "openai" not in root:
    print("missing")
    raise SystemExit(0)

entry = root["openai"]
valid = (
    isinstance(entry, dict)
    and entry.get("type") == "oauth"
    and isinstance(entry.get("access"), str)
    and bool(entry["access"].strip())
    and isinstance(entry.get("refresh"), str)
    and bool(entry["refresh"].strip())
    and isinstance(entry.get("expires"), int)
    and not isinstance(entry.get("expires"), bool)
    and entry["expires"] > 0
    and (
        "accountId" not in entry
        or entry["accountId"] is None
        or isinstance(entry["accountId"], str)
    )
)
if not valid:
    raise SystemExit(f"ERROR: Invalid OpenAI OAuth entry in ai-memory auth file: {path}")

print("ready")
PY
}

ai_memory_profile_spec() {
  case "$1" in
    openai-subscription-luna)
      printf '%s\n' 'openai-oauth|gpt-5.6-luna|openai-oauth'
      ;;
    opencode-go-deepseek)
      printf '%s\n' 'opencode|deepseek-v4-flash|opencode-api-key'
      ;;
    openai-api-luna)
      printf '%s\n' 'openai|gpt-5.6-luna|openai-api-key'
      ;;
    disabled)
      printf '%s\n' '||disabled'
      ;;
    *)
      return 1
      ;;
  esac
}

ai_memory_profile_credential_ready() {
  case "$1" in
    openai-oauth)
      local oauth_state
      oauth_state="$(ai_memory_openai_oauth_state)" || \
        die "Invalid ai-memory OpenAI OAuth state. Repair $AI_MEMORY_AUTH_FILE or log in again before apply."
      [[ "$oauth_state" == "ready" ]]
      ;;
    opencode-api-key)
      ai_memory_env_has_nonempty_value OPENCODE_API_KEY
      ;;
    openai-api-key)
      ai_memory_env_has_nonempty_value OPENAI_API_KEY
      ;;
    disabled)
      return 1
      ;;
    *)
      return 1
      ;;
  esac
}

configure_ai_memory_env_file() {
  local profile profile_spec provider model credential provider_state
  ensure_ai_memory_env_file
  log "Converging the ai-memory provider and paid-job policy"

  profile="$(ai_memory_env_value DOTFILES_AI_MEMORY_LLM_PROFILE 2>/dev/null || true)"
  profile="${profile:-$AI_MEMORY_DEFAULT_LLM_PROFILE}"
  profile_spec="$(ai_memory_profile_spec "$profile")" || \
    die "Unsupported DOTFILES_AI_MEMORY_LLM_PROFILE '$profile'. Use openai-subscription-luna, opencode-go-deepseek, openai-api-luna, or disabled."
  IFS='|' read -r provider model credential <<<"$profile_spec"

  provider_state="zero-llm"
  if ai_memory_profile_credential_ready "$credential"; then
    provider_state="enabled"
  else
    provider=""
  fi

  provider_state="$(python3 - \
    "$AI_MEMORY_ENV_FILE" \
    "$profile" \
    "$provider" \
    "$model" \
    "$provider_state" <<'PY'
import os
import re
import sys
import tempfile
from pathlib import Path

path = Path(sys.argv[1])
profile = sys.argv[2]
provider = sys.argv[3]
model = sys.argv[4]
provider_state = sys.argv[5]
assignment = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*?)\s*$")
managed_names = {
    "DOTFILES_AI_MEMORY_LLM_PROFILE",
    "AI_MEMORY_LLM_PROVIDER",
    "AI_MEMORY_LLM_MODEL",
    "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL",
    "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED",
}
managed_comment = "# Managed by dotfiles/agents/apply.sh."


try:
    original_lines = path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read ai-memory environment file at {path}: {exc}")

kept_lines = []
for line in original_lines:
    if line == managed_comment:
        continue
    match = None if line.lstrip().startswith("#") else assignment.match(line)
    if match is not None and match.group(1) in managed_names:
        continue
    kept_lines.append(line)

while kept_lines and not kept_lines[-1].strip():
    kept_lines.pop()
if kept_lines:
    kept_lines.append("")

kept_lines.extend(
    [
        managed_comment,
        f"DOTFILES_AI_MEMORY_LLM_PROFILE={profile}",
        "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=true",
        "AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED=false",
        f"AI_MEMORY_LLM_PROVIDER={provider}",
        f"AI_MEMORY_LLM_MODEL={model}",
    ]
)

content = "\n".join(kept_lines) + "\n"
descriptor, temporary_name = tempfile.mkstemp(prefix=".env.", dir=path.parent)
try:
    os.fchmod(descriptor, 0o600)
    with os.fdopen(descriptor, "w", encoding="utf-8") as temporary_file:
        temporary_file.write(content)
        temporary_file.flush()
        os.fsync(temporary_file.fileno())
    os.replace(temporary_name, path)
except BaseException:
    try:
        os.close(descriptor)
    except OSError:
        pass
    try:
        os.unlink(temporary_name)
    except FileNotFoundError:
        pass
    raise

print(provider_state)
PY
)" || die "Could not configure the ai-memory provider policy"

  if [[ "$provider_state" == "enabled" ]]; then
    log "ai-memory LLM enabled by $profile"
  elif [[ "$profile" == "disabled" ]]; then
    log "ai-memory LLM is disabled by the selected profile"
  elif [[ "$credential" == "openai-oauth" ]]; then
    log "ai-memory remains in zero-LLM mode. Run ai-memory --data-dir $AI_MEMORY_DATA_DIR --config $AI_MEMORY_CONFIG_FILE auth login openai-oauth, then rerun apply."
  elif [[ "$credential" == "opencode-api-key" ]]; then
    log "ai-memory remains in zero-LLM mode. Add OPENCODE_API_KEY to $AI_MEMORY_ENV_FILE, then rerun apply."
  else
    log "ai-memory remains in zero-LLM mode. Add OPENAI_API_KEY to $AI_MEMORY_ENV_FILE, then rerun apply."
  fi
}

initialize_ai_memory() {
  log "Initializing the ai-memory user data layout"

  python3 - "$AI_MEMORY_CONFIG_FILE" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
if path.is_symlink():
    raise SystemExit(f"ERROR: ai-memory config path must not be a symlink: {path}")
if path.exists() and not path.is_file():
    raise SystemExit(f"ERROR: ai-memory config path must be a regular file: {path}")
PY

  mkdir -p "$AI_MEMORY_DATA_DIR" "$(dirname "$AI_MEMORY_CONFIG_FILE")"
  ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    init || die "ai-memory initialization failed"

  chmod 700 "$AI_MEMORY_DATA_DIR" "$(dirname "$AI_MEMORY_CONFIG_FILE")"
  chmod 600 "$AI_MEMORY_CONFIG_FILE"

  configure_ai_memory_env_file
}

start_ai_memory_service() {
  log "Enabling and restarting the ai-memory user service"

  systemctl --user daemon-reload || die "systemd user daemon reload failed"
  systemctl --user enable ai-memory.service || die "ai-memory user service enablement failed"
  systemctl --user restart ai-memory.service || die "ai-memory user service restart failed"
}

wire_ai_memory_to_opencode() {
  log "Installing the ai-memory OpenCode lifecycle plugin"
  ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    install-hooks \
    --agent opencode \
    --server-url "$AI_MEMORY_LOOPBACK_SERVER_URL" \
    --project-strategy repo-root \
    --apply || die "ai-memory OpenCode hook installation failed"

  log "Generating current ai-memory routing instructions"
  ai-memory install-instructions \
    --target "$AI_MEMORY_INSTRUCTIONS_FILE" \
    --no-skills || die "ai-memory instruction installation failed"

  log "Installing current ai-memory Agent Skills"
  ai-memory install-skills \
    --scope global \
    --agent agents || die "ai-memory skill installation failed"
}

setup_ai_memory() {
  initialize_ai_memory
  start_ai_memory_service
  wire_ai_memory_to_opencode
}

install_rtk() {
  if have rtk; then
    log "RTK already installed, skipping"
  else
    log "Installing RTK"
    curl -fsSL "https://raw.githubusercontent.com/rtk-ai/rtk/$RTK_VERSION/install.sh" | sh || die "RTK install failed"
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
    have rtk || die "RTK install did not put rtk on PATH"
  fi

  log "Initializing RTK for OpenCode"
  rtk init -g --opencode || die "RTK OpenCode init failed"
  rtk gain || true
}

install_plannotator() {
  if have plannotator; then
    log "Plannotator already installed, updating"
    curl -fsSL https://plannotator.ai/install.sh | bash -s -- --extras --non-interactive || die "Plannotator update failed"
  else
    log "Installing Plannotator core and extras"
    curl -fsSL https://plannotator.ai/install.sh | bash -s -- --extras --non-interactive || die "Plannotator install failed"
    export PATH="$HOME/.local/bin:$PATH"
    have plannotator || die "Plannotator install did not put plannotator on PATH"
  fi

  log "Installing Plannotator extra skills"
  npx -y skills add backnotprop/plannotator/apps/skills/extra -g -a opencode -y --copy || die "Plannotator extras install failed"

  cleanup_plannotator_cross_harness_side_effects
}

cleanup_plannotator_cross_harness_side_effects() {
  log "Removing non-OpenCode Plannotator installer side effects"

  rm -rf \
    "$HOME/.claude/skills/plannotator-review" \
    "$HOME/.claude/skills/plannotator-annotate" \
    "$HOME/.claude/skills/plannotator-last"

  rm -f \
    "$HOME/.gemini/commands/plannotator-review.toml" \
    "$HOME/.gemini/commands/plannotator-annotate.toml" \
    "$HOME/.gemini/policies/plannotator.toml"

  python3 - <<'PY'
import json
from pathlib import Path

home = Path.home()

codex_hooks = home / ".codex" / "hooks.json"
removed_codex_plannotator_hook = False
if codex_hooks.exists() and "plannotator" in codex_hooks.read_text(encoding="utf-8"):
    codex_hooks.unlink()
    removed_codex_plannotator_hook = True

codex_config = home / ".codex" / "config.toml"
if removed_codex_plannotator_hook and codex_config.exists():
    lines = codex_config.read_text(encoding="utf-8").splitlines()
    lines = [line for line in lines if line.strip() != "hooks = true"]
    codex_config.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

gemini_settings = home / ".gemini" / "settings.json"
if gemini_settings.exists():
    try:
        data = json.loads(gemini_settings.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = None

    if isinstance(data, dict):
        hooks = data.get("hooks")
        if isinstance(hooks, dict):
            before_tool = hooks.get("BeforeTool")
            if isinstance(before_tool, list):
                hooks["BeforeTool"] = [
                    item for item in before_tool
                    if "plannotator" not in json.dumps(item)
                ]
                if not hooks["BeforeTool"]:
                    hooks.pop("BeforeTool")
            if not hooks:
                data.pop("hooks", None)

        gemini_settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

install_plugins() {
  log "Installing plugins"
  install_rtk
  install_plannotator
}

install_skill() {
  local source="$1"
  local name="$2"
  log "Installing/updating skill: $name"

  npx -y skills add "$source" -g -a opencode -s "$name" -y --copy || die "Failed to install skill: $name"
}

install_local_skill() {
  local src_dir="$1"
  local name="$2"
  local dst="$HOME/.agents/skills/$name"
  log "Installing local skill: $name"

  [[ -d "$src_dir" ]] || die "Local skill source not found: $src_dir"

  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src_dir" "$dst"
}


install_cloudflare_skills() {
  log "Installing/updating Cloudflare skills"
  npx -y skills add https://github.com/cloudflare/skills -g -a opencode -y --copy || die "Cloudflare skills install failed"
}

install_required_skills() {
  log "Installing/updating required skills"

  mkdir -p "$HOME/.agents/skills"

  install_local_skill "$DOTFILES_DIR/agents/skills/find-skills" "find-skills"
  install_local_skill "$DOTFILES_DIR/agents/skills/auto-pr-review" "auto-pr-review"

  install_skill "JuliusBrussee/caveman" "caveman"
  install_skill "mattpocock/skills@productivity/grill-me" "grill-me"
  install_skill "mattpocock/skills@engineering/grill-with-docs" "grill-with-docs"
  install_skill "mattpocock/skills@productivity/handoff" "handoff"
  install_skill "mattpocock/skills@engineering/setup-matt-pocock-skills" "setup-matt-pocock-skills"
  install_skill "mattpocock/skills@engineering/tdd" "tdd"
  install_skill "mattpocock/skills@productivity/teach" "teach"
  install_skill "mattpocock/skills@engineering/to-tickets" "to-tickets"
  install_skill "mattpocock/skills@engineering/triage" "triage"
  install_skill "mattpocock/skills@productivity/writing-for-agents" "writing-for-agents"
  install_skill "shadcn/improve" "improve"
  install_skill "boristane/agent-skills" "logging-best-practices"

  install_cloudflare_skills
}

main() {
  log "Starting OpenCode agent stack setup"

  check_prerequisites
  install_opencode
  install_ai_memory
  install_ai_jail
  verify_ai_memory_unauthenticated_loopback
  setup_opencode
  setup_ai_memory
  merge_opencode_shell_override
  install_plugins
  install_required_skills

  log "Setup complete. Open a new Bash shell or source ~/.bash_aliases, then run ./agents/test.sh to verify."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
