#!/usr/bin/env bash
set -Eeuo pipefail

# apply.sh
#
# Deterministic OpenCode setup script.
# Installs OpenCode, ai-memory, RTK, Plannotator, and required skills.
# Installs/updates skills live on every run.
#
# Usage:
#   ./apply.sh
#
# Prerequisites: bun, curl, git, npm, npx, python3, systemctl.
# AUR package installation also needs yay when ai-memory is absent.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
AGENT_STACK_HELPER="$REPO_DIR/lib/agent_stack.py"
SKILLS_MANIFEST="$REPO_DIR/skills.tsv"
RTK_VERSION="${RTK_VERSION:-v0.38.0}"
OPENCODE_MIN_VERSION="${OPENCODE_MIN_VERSION:-2.0.18}"
OPENCODE_INSTALL_URL="https://opencode.ai/v2/install"
OPENCODE_BINARY="${OPENCODE_BINARY:-$HOME/.opencode/bin/opencode}"
OPENCODE_V1_BACKUP_DIR="${OPENCODE_V1_BACKUP_DIR:-$HOME/.local/share/opencode-v1-backup}"
OPENCODE_SERVER_PORT="${OPENCODE_SERVER_PORT:-4096}"
OPENCODE_SERVER_ENABLED="${OPENCODE_SERVER_ENABLED:-false}"
OPENCODE_SERVER_ENV_FILE="${OPENCODE_SERVER_ENV_FILE:-$HOME/.config/opencode/server.env}"
OPENCODE_SERVER_LABEL="com.opencode.server"
OPENCODE_SERVER_LAUNCH_AGENT_FILE="${OPENCODE_SERVER_LAUNCH_AGENT_FILE:-$HOME/Library/LaunchAgents/$OPENCODE_SERVER_LABEL.plist}"
OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE="${OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE:-$HOME/.config/opencode/$OPENCODE_SERVER_LABEL.plist}"
OPENCODE_SERVER_LAUNCH_DAEMON_FILE="${OPENCODE_SERVER_LAUNCH_DAEMON_FILE:-/Library/LaunchDaemons/$OPENCODE_SERVER_LABEL.plist}"
OPENCODE_SERVER_LOG_DIR="${OPENCODE_SERVER_LOG_DIR:-$HOME/Library/Logs/opencode}"
GITHUB_MCP_TOKEN_FILE="$HOME/.config/opencode/secrets/github-mcp-pat"
GITHUB_MCP_TOKEN_REFERENCE="~/.config/opencode/secrets/github-mcp-pat"
AI_MEMORY_AUR_PACKAGE="${AI_MEMORY_AUR_PACKAGE:-ai-memory-bin}"
AI_MEMORY_MIN_VERSION="${AI_MEMORY_MIN_VERSION:-1.28.0}"
AI_MEMORY_RELEASE_VERSION="${AI_MEMORY_RELEASE_VERSION:-2.1.1}"
AI_MEMORY_RELEASE_BASE_URL="https://github.com/akitaonrails/ai-memory/releases/download/v$AI_MEMORY_RELEASE_VERSION"
AI_MEMORY_MACOS_AARCH64_SHA256="1cc2acdbbd62cc7ecf6e1fe91515ea77786910b2c102f1fe8781aa6c0357eb64"
AI_MEMORY_MACOS_X86_64_SHA256="3c2ca543abdf964c7fe4471e54824876d7327a04d0f222327ad6a8f010f78910"
AI_MEMORY_INSTALL_ROOT="${AI_MEMORY_INSTALL_ROOT:-$HOME/.local/opt/ai-memory/$AI_MEMORY_RELEASE_VERSION}"
AI_MEMORY_BINARY="${AI_MEMORY_BINARY:-$HOME/.local/bin/ai-memory}"
AI_MEMORY_DATA_DIR="$HOME/.local/share/ai-memory"
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
AI_MEMORY_LOOPBACK_SERVER_URL="http://127.0.0.1:49374"
AI_MEMORY_SERVER_URL="${AI_MEMORY_SERVER_URL:-$AI_MEMORY_LOOPBACK_SERVER_URL}"
AI_MEMORY_AUTH_TOKEN_FILE="${AI_MEMORY_AUTH_TOKEN_FILE:-$HOME/.config/ai-memory/client-token}"
AI_MEMORY_AUTH_TOKEN_REFERENCE="~/.config/ai-memory/client-token"
AI_MEMORY_INSTRUCTIONS_FILE="$HOME/.config/opencode/ai-memory.md"
AI_MEMORY_INSTRUCTIONS_REFERENCE="~/.config/opencode/ai-memory.md"
AI_MEMORY_USER_SERVICE_FILE="$HOME/.config/systemd/user/ai-memory.service"
AI_MEMORY_LAUNCH_AGENT_LABEL="com.github.akitaonrails.ai-memory"
AI_MEMORY_LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/$AI_MEMORY_LAUNCH_AGENT_LABEL.plist"
AI_MEMORY_LAUNCH_DAEMON_LABEL="com.github.akitaonrails.ai-memory"
AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="${AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE:-$HOME/.config/ai-memory/$AI_MEMORY_LAUNCH_DAEMON_LABEL.plist}"
AI_MEMORY_LAUNCH_DAEMON_FILE="${AI_MEMORY_LAUNCH_DAEMON_FILE:-/Library/LaunchDaemons/$AI_MEMORY_LAUNCH_DAEMON_LABEL.plist}"
AI_MEMORY_LAUNCH_DAEMON_LOG_DIR="$HOME/Library/Logs/ai-memory"
AI_MEMORY_DEFAULT_LLM_PROFILE="opencode-go-deepseek-v4.1-flash"
BUN_MIN_VERSION="${BUN_MIN_VERSION:-1.3.0}"
LEARN_REPOSITORY_URL="${LEARN_REPOSITORY_URL:-https://github.com/guisaliba/learn.git}"
LEARN_BRANCH="${LEARN_BRANCH:-main}"
LEARN_INSTALL_DIR="${LEARN_INSTALL_DIR:-$HOME/.local/share/opencode/learn}"
LEARN_PLUGIN_SPEC="$LEARN_INSTALL_DIR"
LEARN_LEGACY_PLUGIN_BASE="github:guisaliba/learn"
LEARN_OLDER_PLUGIN_BASE="github:guisaliba/opencode-learn"
PLANNOTATOR_PLUGIN_SPEC="@plannotator/opencode@latest"
OPENCODE_TUI_THEME="orng"
OPENCODE_THEMES_SOURCE_DIR="$REPO_DIR/opencode/themes"
BASH_ALIASES_SOURCE="${BASH_ALIASES_SOURCE:-$REPO_DIR/shell/opencode.bash}"
BASH_ALIASES_FILE="$HOME/.bash_aliases"
OPENCODE_SHELL_BLOCK_START="# >>> dotfiles OpenCode ai-memory wrapper >>>"
OPENCODE_SHELL_BLOCK_END="# <<< dotfiles OpenCode ai-memory wrapper <<<"
BASH_PROFILE="$HOME/.bash_profile"
BASH_PROFILE_BLOCK_START="# >>> guisaliba/agents Bash aliases >>>"
BASH_PROFILE_BLOCK_END="# <<< guisaliba/agents Bash aliases <<<"
GOOGLE_CHROME_APP_PATH="${GOOGLE_CHROME_APP_PATH:-/Applications/Google Chrome.app}"

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

agent_stack_platform() {
  uname -s
}

prepend_path() {
  local directory="$1" entry new_path="$1"
  local path_entries=()
  IFS=: read -r -a path_entries <<<"$PATH"
  for entry in "${path_entries[@]}"; do
    [[ "$entry" == "$directory" ]] && continue
    new_path="$new_path:$entry"
  done
  PATH="$new_path"
  export PATH
}

prepare_platform_prerequisites() {
  local brew_prefix
  case "$(agent_stack_platform)" in
    Linux) ;;
    Darwin)
      have brew || die "Homebrew is required on macOS. Install it from https://brew.sh before running this script."
      brew_prefix="$(brew --prefix)" || die "Could not resolve the Homebrew prefix"
      if [[ ! -x "$brew_prefix/bin/bash" ]]; then
        log "Installing Homebrew Bash"
        brew install bash || die "Homebrew Bash installation failed"
      fi
      if [[ ! -x "$brew_prefix/bin/python3" ]] || \
        ! "$brew_prefix/bin/python3" -c 'import tomllib' >/dev/null 2>&1; then
        log "Installing Homebrew Python"
        brew install python || die "Homebrew Python installation failed"
      fi
      [[ -x "$brew_prefix/bin/bash" ]] || die "Homebrew did not install Bash at $brew_prefix/bin/bash"
      "$brew_prefix/bin/python3" -c 'import tomllib' >/dev/null 2>&1 || \
        die "Homebrew did not install Python 3.11 or newer at $brew_prefix/bin/python3"
      prepend_path "$brew_prefix/bin"
      prepend_path "$HOME/bin"
      prepend_path "$HOME/.local/bin"
      prepend_path "$HOME/.opencode/bin"
      ;;
    *) die "Unsupported operating system: $(agent_stack_platform)" ;;
  esac
}

prepare_full_stack_prerequisites() {
  case "$(agent_stack_platform)" in
    Linux) ;;
    Darwin)
      if [[ ! -d "$GOOGLE_CHROME_APP_PATH" ]]; then
        have brew || die "Homebrew is required to install Google Chrome on macOS"
        log "Installing Google Chrome"
        brew install --cask google-chrome || die "Google Chrome installation failed"
      fi
      [[ -d "$GOOGLE_CHROME_APP_PATH" ]] || \
        die "Google Chrome is missing at $GOOGLE_CHROME_APP_PATH"
      ;;
    *) die "Unsupported operating system: $(agent_stack_platform)" ;;
  esac
}

check_prerequisites() {
  log "Checking prerequisites"
  local cmd platform missing=()
  local commands=(bash bun curl git npm npx python3)
  platform="$(agent_stack_platform)"
  case "$platform" in
    Linux) commands+=(systemctl) ;;
    Darwin) commands+=(brew launchctl) ;;
    *) die "Unsupported operating system: $platform" ;;
  esac
  for cmd in "${commands[@]}"; do
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

file_sha256() {
  local output
  if have sha256sum; then
    output="$(sha256sum "$1")" || return 1
  elif have shasum; then
    output="$(shasum -a 256 "$1")" || return 1
  else
    return 1
  fi
  printf '%s\n' "${output%%[[:space:]]*}"
}

ai_memory_macos_release_spec() {
  case "$(uname -m)" in
    arm64|aarch64)
      printf '%s\t%s\n' "ai-memory-macos-aarch64.tar.gz" "$AI_MEMORY_MACOS_AARCH64_SHA256"
      ;;
    x86_64)
      printf '%s\t%s\n' "ai-memory-macos-x86_64.tar.gz" "$AI_MEMORY_MACOS_X86_64_SHA256"
      ;;
    *)
      die "ai-memory $AI_MEMORY_RELEASE_VERSION does not support macOS architecture $(uname -m)"
      ;;
  esac
}

install_ai_memory_macos() {
  local release_spec asset expected_sha download_url archive temporary_dir actual_sha
  local existing_command installed_version

  release_spec="$(ai_memory_macos_release_spec)"
  IFS=$'\t' read -r asset expected_sha <<<"$release_spec"
  download_url="$AI_MEMORY_RELEASE_BASE_URL/$asset"

  existing_command="$(type -P ai-memory 2>/dev/null || true)"
  if [[ -n "$existing_command" && "$existing_command" != "$AI_MEMORY_BINARY" ]]; then
    die "ai-memory already resolves to an unmanaged executable at $existing_command; $AI_MEMORY_BINARY was not installed."
  fi
  if [[ -e "$AI_MEMORY_BINARY" && ! -L "$AI_MEMORY_BINARY" ]]; then
    die "Managed macOS ai-memory path must be a symlink: $AI_MEMORY_BINARY"
  fi
  if [[ -L "$AI_MEMORY_BINARY" && "$(readlink "$AI_MEMORY_BINARY")" != "$AI_MEMORY_INSTALL_ROOT/ai-memory" ]]; then
    die "Managed macOS ai-memory symlink points outside the pinned release: $AI_MEMORY_BINARY"
  fi

  if [[ -d "$AI_MEMORY_INSTALL_ROOT" ]]; then
    [[ -x "$AI_MEMORY_INSTALL_ROOT/ai-memory" ]] || \
      die "Existing ai-memory release bundle is incomplete: $AI_MEMORY_INSTALL_ROOT"
    [[ -d "$AI_MEMORY_INSTALL_ROOT/hooks/opencode" ]] || \
      die "Existing ai-memory release bundle has no OpenCode hooks: $AI_MEMORY_INSTALL_ROOT"
    installed_version="$("$AI_MEMORY_INSTALL_ROOT/ai-memory" --version 2>/dev/null || true)"
    [[ "$installed_version" == *"$AI_MEMORY_RELEASE_VERSION"* ]] || \
      die "Existing ai-memory release bundle does not report version $AI_MEMORY_RELEASE_VERSION"
  elif [[ -e "$AI_MEMORY_INSTALL_ROOT" ]]; then
    die "ai-memory release path must be a directory: $AI_MEMORY_INSTALL_ROOT"
  else
    mkdir -p "$(dirname "$AI_MEMORY_INSTALL_ROOT")"
    (
      archive="$(mktemp "$(dirname "$AI_MEMORY_INSTALL_ROOT")/.ai-memory.$AI_MEMORY_RELEASE_VERSION.XXXXXX.tar.gz")"
      temporary_dir="$(mktemp -d "$(dirname "$AI_MEMORY_INSTALL_ROOT")/.ai-memory.$AI_MEMORY_RELEASE_VERSION.XXXXXX")"
      trap 'rm -rf -- "$archive" "$temporary_dir"' EXIT
      curl --fail --location --silent --show-error --output "$archive" "$download_url" || \
        die "Could not download ai-memory $AI_MEMORY_RELEASE_VERSION from $download_url"
      actual_sha="$(file_sha256 "$archive")" || die "Could not calculate the ai-memory archive digest"
      [[ "$actual_sha" == "$expected_sha" ]] || die "ai-memory archive digest did not match $asset"
      tar -xzf "$archive" -C "$temporary_dir" || die "Could not extract the ai-memory release archive"
      [[ -x "$temporary_dir/ai-memory" ]] || die "ai-memory release archive has no executable"
      [[ -d "$temporary_dir/hooks/opencode" ]] || die "ai-memory release archive has no OpenCode hooks"
      installed_version="$("$temporary_dir/ai-memory" --version 2>/dev/null || true)"
      [[ "$installed_version" == *"$AI_MEMORY_RELEASE_VERSION"* ]] || \
        die "Downloaded ai-memory does not report version $AI_MEMORY_RELEASE_VERSION"
      mv "$temporary_dir" "$AI_MEMORY_INSTALL_ROOT" || die "Could not install ai-memory at $AI_MEMORY_INSTALL_ROOT"
      temporary_dir=""
      rm -f -- "$archive"
      archive=""
      trap - EXIT
    ) || return 1
  fi

  [[ -x "$AI_MEMORY_INSTALL_ROOT/ai-memory" ]] || \
    die "Installed ai-memory release bundle is incomplete: $AI_MEMORY_INSTALL_ROOT"
  [[ -d "$AI_MEMORY_INSTALL_ROOT/hooks/opencode" ]] || \
    die "Installed ai-memory release bundle has no OpenCode hooks: $AI_MEMORY_INSTALL_ROOT"
  mkdir -p "$(dirname "$AI_MEMORY_BINARY")"
  if [[ ! -L "$AI_MEMORY_BINARY" ]]; then
    ln -s "$AI_MEMORY_INSTALL_ROOT/ai-memory" "$AI_MEMORY_BINARY" || \
      die "Could not link ai-memory at $AI_MEMORY_BINARY"
  fi
}

verify_native_ai_memory() {
  local executable platform
  executable="$(type -P ai-memory)" || \
    die "ai-memory must resolve to an executable file on PATH"
  platform="$(agent_stack_platform)"

  python3 - "$executable" "$platform" <<'PY' || \
    die "ai-memory must be a native $platform executable. Use the upstream Docker wrapper as a separate deployment, not with this native user-service setup."
import sys
from pathlib import Path

try:
    magic = Path(sys.argv[1]).read_bytes()[:4]
except OSError:
    raise SystemExit(1)

platform = sys.argv[2]
valid_magic = {
    "Linux": {b"\x7fELF"},
    "Darwin": {
        b"\xfe\xed\xfa\xce",
        b"\xce\xfa\xed\xfe",
        b"\xfe\xed\xfa\xcf",
        b"\xcf\xfa\xed\xfe",
        b"\xca\xfe\xba\xbe",
        b"\xbe\xba\xfe\xca",
    },
}
raise SystemExit(0 if magic in valid_magic.get(platform, set()) else 1)
PY
}

install_ai_memory() {
  case "$(agent_stack_platform)" in
    Linux) install_aur_command ai-memory "$AI_MEMORY_AUR_PACKAGE" ;;
    Darwin) install_ai_memory_macos ;;
    *) die "Unsupported operating system: $(agent_stack_platform)" ;;
  esac
  verify_native_ai_memory
  require_minimum_version ai-memory "$AI_MEMORY_MIN_VERSION"
}

report_optional_ai_jail() {
  if have ai-jail; then
    log "Optional ai-jail command available for sandboxed dangerous-mode sessions"
  else
    log "Optional ai-jail command unavailable; sandboxed dangerous-mode sessions are disabled"
  fi
}

verify_ai_memory_no_static_auth_files() {
  python3 - \
    "$AI_MEMORY_CONFIG_FILE" \
    "$AI_MEMORY_ENV_FILE" \
    "$AGENT_STACK_HELPER" <<'PY'
import sys
import tomllib
from pathlib import Path

config_path = Path(sys.argv[1])
env_path = Path(sys.argv[2])
helper_path = Path(sys.argv[3])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import parse_env_assignment

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

    auth_names = {
        "AI_MEMORY_AUTH_TOKEN",
        "AI_MEMORY_AUTH__BEARER_TOKEN",
        "AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN",
    }
    for line in lines:
        assignment = parse_env_assignment(line)
        if assignment is None:
            continue
        name, value = assignment
        if name not in auth_names:
            continue
        if value.strip():
            raise SystemExit(
                f"ERROR: {env_path} sets {name}; "
                "this loopback integration must stay unauthenticated"
            )
PY
}

verify_ai_memory_unauthenticated_loopback() {
  local auth_variable

  # A host that runs the OpenCode server and the ai-memory store is the server
  # host. It requires a token, and it keeps one in its environment file.
  if [[ "$OPENCODE_SERVER_ENABLED" == true ]]; then
    ensure_ai_memory_env_file
    [[ -n "$(ai_memory_env_value AI_MEMORY_AUTH_TOKEN 2>/dev/null || true)" ]] || \
      die "The ai-memory service on this server host requires AI_MEMORY_AUTH_TOKEN in $AI_MEMORY_ENV_FILE"
    return 0
  fi

  # A host pointed at a remote ai-memory server is a client host. It is not
  # loopback, so the unauthenticated policy does not apply. The ai-memory CLI
  # reads its bearer from the environment, so a client must be allowed to carry
  # one; forbidding it made a client unable to reach the server at all.
  if [[ "$AI_MEMORY_SERVER_URL" != "$AI_MEMORY_LOOPBACK_SERVER_URL" ]]; then
    log "Verifying the authenticated ai-memory client policy for $AI_MEMORY_SERVER_URL"
    if [[ -z "${AI_MEMORY_AUTH_TOKEN:-}" ]] && \
      ! ai_memory_env_has_nonempty_value AI_MEMORY_AUTH_TOKEN && \
      [[ ! -s "$AI_MEMORY_AUTH_TOKEN_FILE" ]]; then
      die "This client host requires an ai-memory bearer token to reach $AI_MEMORY_SERVER_URL. Put one in $AI_MEMORY_AUTH_TOKEN_FILE, or export AI_MEMORY_AUTH_TOKEN, then re-run apply."
    fi
    return 0
  fi

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

  if [[ "$(agent_stack_platform)" == "Darwin" ]]; then
    return 0
  fi

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

opencode_major_version() {
  local executable="$1" output
  output="$("$executable" --version 2>/dev/null)" || return 1
  python3 - "$output" <<'PY'
import re
import sys

match = re.search(r"(?:^|\s)v?(\d+)\.(\d+)\.(\d+)(?:\s|$)", sys.argv[1])
if not match:
    raise SystemExit(1)
print(match.group(1))
PY
}

backup_opencode_v1_state() {
  local active_binary="${1:-}" marker="$OPENCODE_V1_BACKUP_DIR/manifest.txt"
  [[ -e "$marker" ]] && return 0

  log "Backing up the OpenCode V1 runtime before conversion"
  mkdir -p "$OPENCODE_V1_BACKUP_DIR"
  if [[ -n "$active_binary" && -x "$active_binary" ]]; then
    cp "$active_binary" "$OPENCODE_V1_BACKUP_DIR/opencode"
    chmod 700 "$OPENCODE_V1_BACKUP_DIR/opencode"
  fi
  for path in \
    "$HOME/.config/opencode/opencode.json" \
    "$HOME/.config/opencode/opencode.jsonc" \
    "$HOME/.config/opencode/tui.json" \
    "$HOME/.config/opencode/tui.jsonc"
  do
    [[ -f "$path" ]] && cp "$path" "$OPENCODE_V1_BACKUP_DIR/$(basename "$path")"
  done
  [[ -d "$HOME/.config/opencode/plugins" ]] && \
    cp -a "$HOME/.config/opencode/plugins" "$OPENCODE_V1_BACKUP_DIR/plugins"
  if [[ -f "$HOME/.local/share/opencode/opencode.db" ]] && have sqlite3; then
    sqlite3 "$HOME/.local/share/opencode/opencode.db" \
      ".backup '$OPENCODE_V1_BACKUP_DIR/opencode.db'"
    chmod 600 "$OPENCODE_V1_BACKUP_DIR/opencode.db"
  fi
  [[ ! -f "$HOME/.local/share/opencode/auth.json" ]] || \
    cp "$HOME/.local/share/opencode/auth.json" "$OPENCODE_V1_BACKUP_DIR/auth.json"
  {
    printf 'version='
    [[ -n "$active_binary" && -x "$active_binary" ]] && "$active_binary" --version || printf 'not-installed\n'
    printf 'binary=%s\n' "$active_binary"
  } >"$marker"
  chmod -R go-rwx "$OPENCODE_V1_BACKUP_DIR"
}

install_opencode() {
  local active_binary="" active_major="" managed_major=""
  active_binary="$(type -P opencode 2>/dev/null || true)"
  [[ -z "$active_binary" ]] || active_major="$(opencode_major_version "$active_binary" || true)"
  [[ ! -x "$OPENCODE_BINARY" ]] || managed_major="$(opencode_major_version "$OPENCODE_BINARY" || true)"

  if [[ "$active_major" == "1" ]]; then
    backup_opencode_v1_state "$active_binary"
  elif [[ "$managed_major" == "1" ]]; then
    backup_opencode_v1_state "$OPENCODE_BINARY"
  fi

  if [[ "$managed_major" == "2" ]]; then
    prepend_path "$(dirname "$OPENCODE_BINARY")"
  else
    log "Installing OpenCode V2 with the official installer"
    curl -fsSL "$OPENCODE_INSTALL_URL" | bash -s -- --no-modify-path || \
      die "OpenCode V2 installation failed"
    prepend_path "$(dirname "$OPENCODE_BINARY")"
  fi

  [[ -x "$OPENCODE_BINARY" ]] || die "OpenCode V2 installer did not create $OPENCODE_BINARY"
  [[ "$(opencode_major_version "$OPENCODE_BINARY" || true)" == "2" ]] || \
    die "$OPENCODE_BINARY is not OpenCode V2"
  [[ "$(type -P opencode)" == "$OPENCODE_BINARY" ]] || \
    die "OpenCode V2 is installed but another opencode binary still has PATH precedence"
  require_minimum_version opencode "$OPENCODE_MIN_VERSION"
}

sync_learn_plugin() {
  local actual_remote expected_remote checkout_root required

  log "Updating the managed OpenCode Learn checkout"

  [[ "$LEARN_INSTALL_DIR" = /* ]] || \
    die "LEARN_INSTALL_DIR must be an absolute path: $LEARN_INSTALL_DIR"

  if [[ -L "$LEARN_INSTALL_DIR" ]]; then
    die "Learn install directory must not be a symlink: $LEARN_INSTALL_DIR"
  fi

  if [[ ! -e "$LEARN_INSTALL_DIR" ]]; then
    mkdir -p "$(dirname "$LEARN_INSTALL_DIR")"
    git clone --branch "$LEARN_BRANCH" --single-branch \
      "$LEARN_REPOSITORY_URL" "$LEARN_INSTALL_DIR" || \
      die "Could not clone OpenCode Learn from $LEARN_REPOSITORY_URL"
  else
    [[ -d "$LEARN_INSTALL_DIR" ]] || \
      die "Learn install path is not a directory: $LEARN_INSTALL_DIR"

    git -C "$LEARN_INSTALL_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || \
      die "Learn install directory is not a Git checkout: $LEARN_INSTALL_DIR"
    checkout_root="$(git -C "$LEARN_INSTALL_DIR" rev-parse --show-toplevel)" || \
      die "Could not resolve Learn checkout root: $LEARN_INSTALL_DIR"
    [[ "$(cd "$checkout_root" && pwd -P)" == "$(cd "$LEARN_INSTALL_DIR" && pwd -P)" ]] || \
      die "Learn install directory must be the Git worktree root: $LEARN_INSTALL_DIR"

    actual_remote="$(git -C "$LEARN_INSTALL_DIR" remote get-url origin 2>/dev/null)" || \
      die "Learn checkout has no origin remote: $LEARN_INSTALL_DIR"
    read -r actual_remote expected_remote < <(
      python3 - "$actual_remote" "$LEARN_REPOSITORY_URL" <<'PY'
from urllib.parse import urlparse
import sys


def identity(value):
    value = value.strip()
    if value.startswith("git@") and ":" in value:
        user_host, path = value.split(":", 1)
        value = f"{user_host.split('@', 1)[-1]}/{path}"
    elif value.startswith("ssh://"):
        parsed = urlparse(value)
        value = f"{parsed.hostname or ''}{parsed.path}"
    elif "://" in value:
        parsed = urlparse(value)
        value = f"{parsed.hostname or parsed.netloc}{parsed.path}"
    return value.rstrip("/").removesuffix(".git")


print(identity(sys.argv[1]), identity(sys.argv[2]))
PY
    )
    [[ "$actual_remote" == "$expected_remote" ]] || \
      die "Learn checkout origin does not match $LEARN_REPOSITORY_URL: $actual_remote"
    [[ "$(git -C "$LEARN_INSTALL_DIR" branch --show-current)" == "$LEARN_BRANCH" ]] || \
      die "Learn checkout must use branch $LEARN_BRANCH: $LEARN_INSTALL_DIR"
    [[ -z "$(git -C "$LEARN_INSTALL_DIR" status --porcelain --untracked-files=all)" ]] || \
      die "Learn checkout has uncommitted changes; refusing to update: $LEARN_INSTALL_DIR"

    git -C "$LEARN_INSTALL_DIR" fetch --prune origin "$LEARN_BRANCH" || \
      die "Could not fetch OpenCode Learn branch $LEARN_BRANCH"
    git -C "$LEARN_INSTALL_DIR" merge --ff-only "origin/$LEARN_BRANCH" || \
      die "Learn checkout cannot fast-forward to origin/$LEARN_BRANCH"
  fi

  for required in package.json bun.lock src/server.ts src/tui.ts; do
    [[ -f "$LEARN_INSTALL_DIR/$required" ]] || \
      die "Learn checkout is missing required file: $LEARN_INSTALL_DIR/$required"
  done

  (
    cd "$LEARN_INSTALL_DIR"
    PUPPETEER_SKIP_DOWNLOAD=true bun install --frozen-lockfile
  ) || die "Could not install OpenCode Learn dependencies"

  [[ -f "$LEARN_INSTALL_DIR/node_modules/@opencode-ai/plugin/package.json" ]] || \
    die "OpenCode Learn dependencies are incomplete: @opencode-ai/plugin is missing"
}

merge_opencode_shell_override() {
  log "Making interactive Bash OpenCode starts use ai-memory managed workstreams"

  python3 - \
    "$BASH_ALIASES_SOURCE" \
    "$BASH_ALIASES_FILE" \
    "$OPENCODE_SHELL_BLOCK_START" \
    "$OPENCODE_SHELL_BLOCK_END" \
    "$AGENT_STACK_HELPER" <<'PY'
import stat
import sys
from pathlib import Path

source_path = Path(sys.argv[1])
target_path = Path(sys.argv[2])
start_marker = sys.argv[3]
end_marker = sys.argv[4]
helper_path = Path(sys.argv[5])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text


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
atomic_write_text(target_path, content, target_mode, ".bash_aliases.")
PY
}

# Every platform needs this block, not only macOS. The ai-memory CLI reads
# AI_MEMORY_SERVER_URL and AI_MEMORY_AUTH_TOKEN from the environment, never from
# the environment file, so a client host whose login shell does not source that
# file cannot reach the server at all. Guarding this on Darwin left Linux clients
# unable to start a managed workstream.
configure_bash_login_env() {
  log "Making login Bash load the managed shell and ai-memory environment"
  python3 - \
    "$BASH_PROFILE" \
    "$BASH_PROFILE_BLOCK_START" \
    "$BASH_PROFILE_BLOCK_END" \
    "$AGENT_STACK_HELPER" <<'PY'
import stat
import sys
from pathlib import Path

path = Path(sys.argv[1])
start_marker = sys.argv[2]
end_marker = sys.argv[3]
helper_path = Path(sys.argv[4])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text


if path.is_symlink():
    raise SystemExit(f"ERROR: Bash profile must be a regular file: {path}")
if path.exists() and not path.is_file():
    raise SystemExit(f"ERROR: Bash profile must be a regular file: {path}")

if path.exists():
    text = path.read_text(encoding="utf-8")
    mode = stat.S_IMODE(path.stat().st_mode)
else:
    text = ""
    mode = 0o644

lines = text.splitlines()
starts = [index for index, line in enumerate(lines) if line == start_marker]
ends = [index for index, line in enumerate(lines) if line == end_marker]
if starts or ends:
    if len(starts) != 1 or len(ends) != 1 or ends[0] <= starts[0]:
        raise SystemExit(
            f"ERROR: Expected one balanced Bash profile block in {path}; "
            "file was not changed"
        )
    kept = lines[: starts[0]] + lines[ends[0] + 1 :]
else:
    kept = lines

while kept and not kept[-1].strip():
    kept.pop()
if kept:
    kept.append("")
kept.extend(
    [
        start_marker,
        'if [[ -f "$HOME/.bash_aliases" ]]; then',
        '  source "$HOME/.bash_aliases"',
        "fi",
        'if [[ -f "$HOME/.profile" ]]; then',
        '  source "$HOME/.profile"',
        "fi",
        'if [[ -f "$HOME/.config/ai-memory/env" ]]; then',
        '  set -a',
        '  source "$HOME/.config/ai-memory/env"',
        '  set +a',
        "fi",
        '# The long-lived OpenCode server needs a password for web and phone.',
        '# The TUI uses a private server and does not attach to it.',
        'if [[ -f "$HOME/.config/opencode/server.env" ]]; then',
        '  set -a',
        '  source "$HOME/.config/opencode/server.env"',
        '  set +a',
        "fi",
        '# The ai-memory CLI reads its bearer from the environment, never from the',
        '# token file, so a client host needs the token exported for `ai-memory run`.',
        '# Read it here instead of asking the operator to paste a secret into this',
        '# file, and strip the trailing newline the 0600 token file carries.',
        'if [[ -f "$HOME/.config/ai-memory/client-token" ]]; then',
        '  AI_MEMORY_AUTH_TOKEN="$(tr -d \' \\r\\n\' < "$HOME/.config/ai-memory/client-token")"',
        '  export AI_MEMORY_AUTH_TOKEN',
        "fi",
        end_marker,
    ]
)
content = "\n".join(kept) + "\n"
if content == text:
    raise SystemExit(0)

atomic_write_text(path, content, mode, ".bash_profile.")
PY
}

ensure_opencode_server_env_file() {
  log "Preparing the machine-local OpenCode server environment file"
  python3 "$AGENT_STACK_HELPER" \
    ensure-private-file \
    "$OPENCODE_SERVER_ENV_FILE" \
    "OpenCode server environment path"
}

opencode_server_env_value() {
  python3 "$AGENT_STACK_HELPER" env-value "$OPENCODE_SERVER_ENV_FILE" "$1"
}

install_opencode_launch_daemon_source() {
  [[ "$OPENCODE_SERVER_ENABLED" == true ]] || return 0
  [[ "$(agent_stack_platform)" == Darwin ]] || \
    die "The centralized OpenCode server currently requires macOS"

  ensure_opencode_server_env_file
  [[ -n "$(opencode_server_env_value OPENCODE_SERVER_PASSWORD 2>/dev/null || true)" ]] || \
    die "Set OPENCODE_SERVER_PASSWORD in $OPENCODE_SERVER_ENV_FILE before enabling the server"

  local username group
  username="$(id -un)"
  group="$(id -gn)"
  log "Generating the OpenCode V2 LaunchDaemon source"
  mkdir -p "$(dirname "$OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE")" "$OPENCODE_SERVER_LOG_DIR"
  chmod 700 "$OPENCODE_SERVER_LOG_DIR"
  touch "$OPENCODE_SERVER_LOG_DIR/stdout.log" "$OPENCODE_SERVER_LOG_DIR/stderr.log"
  chmod 600 "$OPENCODE_SERVER_LOG_DIR/stdout.log" "$OPENCODE_SERVER_LOG_DIR/stderr.log"

  python3 - \
    "$OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE" \
    "$OPENCODE_BINARY" \
    "$OPENCODE_SERVER_ENV_FILE" \
    "$OPENCODE_SERVER_LABEL" \
    "$OPENCODE_SERVER_PORT" \
    "$OPENCODE_SERVER_LOG_DIR" \
    "$HOME" \
    "$username" \
    "$group" \
    "$AGENT_STACK_HELPER" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
binary = str(Path(sys.argv[2]).absolute())
env_file = str(Path(sys.argv[3]).absolute())
label = sys.argv[4]
port = sys.argv[5]
log_dir = sys.argv[6]
home = sys.argv[7]
username = sys.argv[8]
group = sys.argv[9]
helper_path = Path(sys.argv[10])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text

config = {
    "Label": label,
    "UserName": username,
    "GroupName": group,
    "ProgramArguments": [
        "/bin/bash",
        "-c",
        'set -a; source "$1"; shift; exec "$@"',
        "opencode-server",
        env_file,
        binary,
        "serve",
        "--hostname",
        "127.0.0.1",
        "--port",
        port,
    ],
    "RunAtLoad": True,
    "KeepAlive": {"SuccessfulExit": False},
    "WorkingDirectory": home,
    "EnvironmentVariables": {
        "HOME": home,
        "PATH": f"{home}/.opencode/bin:{home}/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
    },
    "StandardOutPath": f"{log_dir}/stdout.log",
    "StandardErrorPath": f"{log_dir}/stderr.log",
}
content = plistlib.dumps(config, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8")
try:
    if path.read_text(encoding="utf-8") == content:
        raise SystemExit(0)
except FileNotFoundError:
    pass

atomic_write_text(path, content, 0o600, ".opencode-launch-daemon.")
PY
  chmod 600 "$OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE"
}

start_opencode_server() {
  [[ "$OPENCODE_SERVER_ENABLED" == true ]] || return 0
  local target="system/$OPENCODE_SERVER_LABEL" contract

  install_opencode_launch_daemon_source
  contract="$(stat -f '%Su:%Sg:%Lp' "$OPENCODE_SERVER_LAUNCH_DAEMON_FILE" 2>/dev/null || true)"
  if [[ "$contract" != "root:wheel:644" ]]; then
    die "OpenCode LaunchDaemon requires one privileged installation. Run:
sudo launchctl bootout '$target' >/dev/null 2>&1 || true
sudo install -o root -g wheel -m 0644 '$OPENCODE_SERVER_LAUNCH_DAEMON_SOURCE_FILE' '$OPENCODE_SERVER_LAUNCH_DAEMON_FILE'
sudo launchctl bootstrap system '$OPENCODE_SERVER_LAUNCH_DAEMON_FILE'
sudo launchctl kickstart -k '$target'"
  fi
  if ! launchctl print "$target" >/dev/null 2>&1; then
    die "OpenCode LaunchDaemon is installed but inactive. Run:
sudo launchctl bootstrap system '$OPENCODE_SERVER_LAUNCH_DAEMON_FILE'
sudo launchctl kickstart -k '$target'"
  fi
  rm -f "$OPENCODE_SERVER_LAUNCH_AGENT_FILE"

  have tailscale || die "Tailscale is required for the centralized OpenCode server"
  tailscale serve --bg --yes "http://127.0.0.1:$OPENCODE_SERVER_PORT" || \
    die "Tailscale Serve configuration failed"
}

copy_agents_md() {
  log "Copying canonical AGENTS.md to OpenCode global config"

  local src="$REPO_DIR/AGENTS.md"
  [[ -f "$src" ]] || die "Missing canonical agent instructions: $src"

  mkdir -p "$HOME/.config/opencode"
  cp "$src" "$HOME/.config/opencode/AGENTS.md"
}

install_opencode_themes() {
  local source_theme target_dir themes=()
  log "Installing vendored OpenCode themes"

  [[ -d "$OPENCODE_THEMES_SOURCE_DIR" ]] || \
    die "Missing vendored OpenCode theme directory: $OPENCODE_THEMES_SOURCE_DIR"

  shopt -s nullglob
  themes=("$OPENCODE_THEMES_SOURCE_DIR"/*.json)
  shopt -u nullglob
  if [[ ${#themes[@]} -eq 0 ]]; then
    die "No vendored OpenCode theme files in: $OPENCODE_THEMES_SOURCE_DIR"
  fi

  target_dir="$HOME/.config/opencode/themes"
  mkdir -p "$target_dir"
  for source_theme in "${themes[@]}"; do
    cp "$source_theme" "$target_dir/"
  done
}

ensure_github_mcp_token_file() {
  log "Preparing the machine-local GitHub MCP token file"

  python3 "$AGENT_STACK_HELPER" \
    ensure-private-file \
    "$GITHUB_MCP_TOKEN_FILE" \
    "GitHub MCP token path"
}

merge_opencode_json() {
  log "Merging OpenCode opencode.json"

  local config="$HOME/.config/opencode/opencode.json"
  local profile subagent_model
  mkdir -p "$(dirname "$config")"

  # On a client the model is the server's decision, so nothing is written here.
  # An empty subagent_model makes the python step leave every agent model alone.
  if agent_stack_is_client_host; then
    agent_stack_profile_owner_note
    subagent_model=""
  else
    profile="$(ai_memory_selected_profile)" || return 1
    subagent_model="$(opencode_subagent_profile_model "$profile")"
  fi

  python3 - \
    "$config" \
    "$subagent_model" \
    "$GITHUB_MCP_TOKEN_REFERENCE" \
    "$AI_MEMORY_SERVER_URL" \
    "$AI_MEMORY_AUTH_TOKEN_REFERENCE" \
    "$LEARN_PLUGIN_SPEC" \
    "$LEARN_LEGACY_PLUGIN_BASE" \
    "$LEARN_OLDER_PLUGIN_BASE" \
    "$PLANNOTATOR_PLUGIN_SPEC" <<'PY'
import json
import os
import sys

path = sys.argv[1]
subagent_model = sys.argv[2]
github_mcp_token_reference = sys.argv[3]
ai_memory_server_url = sys.argv[4].rstrip("/")
ai_memory_auth_token_reference = sys.argv[5]
learn_plugin_spec = sys.argv[6]
learn_legacy_plugin_base = sys.argv[7]
learn_older_plugin_base = sys.argv[8]
plannotator_plugin_spec = sys.argv[9]
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


def convert_permissions(value, location):
    if isinstance(value, list):
        return value
    if isinstance(value, str):
        return [{"action": "*", "resource": "*", "effect": value}]
    if not isinstance(value, dict):
        raise SystemExit(f"ERROR: Expected '{location}' to be an object, array, or string in {path}. File was not changed.")
    action_names = {"bash": "shell", "task": "subagent", "write": "edit", "patch": "edit"}
    result = []
    for action, rule in value.items():
        action = action_names.get(action, action)
        if isinstance(rule, str):
            result.append({"action": action, "resource": "*", "effect": rule})
        elif isinstance(rule, dict):
            for resource, effect in rule.items():
                result.append({"action": action, "resource": resource, "effect": effect})
        else:
            raise SystemExit(f"ERROR: Invalid permission rule at '{location}.{action}' in {path}. File was not changed.")
    return result


def convert_agent(config, location):
    if not isinstance(config, dict):
        raise SystemExit(f"ERROR: Expected '{location}' to be an object in {path}. File was not changed.")
    config = dict(config)
    if "system" not in config and "prompt" in config:
        config["system"] = config.pop("prompt")
    else:
        config.pop("prompt", None)
    if "disabled" not in config and "disable" in config:
        config["disabled"] = config.pop("disable")
    else:
        config.pop("disable", None)
    if "permissions" not in config and "permission" in config:
        config["permissions"] = convert_permissions(config.pop("permission"), f"{location}.permission")
    else:
        config.pop("permission", None)
    variant = config.pop("variant", None)
    if variant and isinstance(config.get("model"), str) and "#" not in config["model"]:
        config["model"] = f'{config["model"]}#{variant}'
    body = {}
    request = config.get("request")
    if request is not None and not isinstance(request, dict):
        raise SystemExit(f"ERROR: Expected '{location}.request' to be an object in {path}. File was not changed.")
    request = dict(request or {})
    if isinstance(request.get("body"), dict):
        body.update(request["body"])
    for key in ("temperature", "top_p"):
        if key in config:
            body.setdefault(key, config.pop(key))
    options = config.pop("options", None)
    if isinstance(options, dict):
        for key, value in options.items():
            body.setdefault(key, value)
    if body:
        request["body"] = body
    if request:
        config["request"] = request
    return config


def convert_plugin(item):
    if isinstance(item, str):
        return item
    if isinstance(item, list) and len(item) == 2 and isinstance(item[0], str) and isinstance(item[1], dict):
        return {"package": item[0], "options": item[1]}
    if isinstance(item, dict) and isinstance(item.get("package"), str):
        return item
    raise SystemExit(f"ERROR: Invalid plugin entry in {path}. File was not changed.")


def plugin_spec(item):
    return item if isinstance(item, str) else item["package"]


if "update" not in data and "autoupdate" in data:
    legacy_update = data.pop("autoupdate")
    data["update"] = "notify" if legacy_update == "notify" else "auto" if legacy_update is True else "disable"
else:
    data.pop("autoupdate", None)

for old, new in (("snapshot", "snapshots"), ("attachment", "media"), ("command", "commands"), ("provider", "providers")):
    if new not in data and old in data:
        data[new] = data.pop(old)
    else:
        data.pop(old, None)

if "permissions" not in data and "permission" in data:
    data["permissions"] = convert_permissions(data.pop("permission"), "permission")
else:
    data.pop("permission", None)

legacy_agents = data.pop("agent", {})
legacy_modes = data.pop("mode", {})
native_agents = data.get("agents", {})
for value, name in ((legacy_agents, "agent"), (legacy_modes, "mode"), (native_agents, "agents")):
    if not isinstance(value, dict):
        raise SystemExit(f"ERROR: Expected '{name}' to be an object in {path}. File was not changed.")
agents = {}
for name, config in {**legacy_modes, **legacy_agents, **native_agents}.items():
    agents[name] = convert_agent(config, f"agents.{name}")

primary_model = "openai/gpt-6-sol"
data["model"] = primary_model
data["default_agent"] = "build"

managed_models = {
    "plan": primary_model,
    "general": subagent_model,
    "explore": subagent_model,
    "title": subagent_model,
}

for name, model in managed_models.items():
    config = agents.get(name, {})
    if not isinstance(config, dict):
        if model:
            raise SystemExit(
                f"ERROR: Expected 'agents.{name}' to be an object in {path}. "
                "File was not changed."
            )
        continue
    if not model:
        # A client host writes no agent model: the server owns it. Drop any model
        # already there rather than leaving a stale one that looks authoritative,
        # and keep every other key in the entry.
        config.pop("model", None)
    else:
        config["model"] = model
    agents[name] = config

# small_model was a V1 title agent, and it was migrated with setdefault, so a
# wrong id written once was never corrected. The title agent now follows the
# selected profile with the rest.
data.pop("small_model", None)
data["agents"] = agents

instructions = data.get("instructions", [])
if not isinstance(instructions, list):
    raise SystemExit(
        f"ERROR: Expected 'instructions' to be an array in {path}. "
        "File was not changed."
    )
data["instructions"] = list(dict.fromkeys(instructions))

legacy_plugins = data.pop("plugin", [])
native_plugins = data.get("plugins", [])
if isinstance(legacy_plugins, str):
    legacy_plugins = [legacy_plugins]
if not isinstance(legacy_plugins, list) or not isinstance(native_plugins, list):
    raise SystemExit(f"ERROR: Expected plugin declarations to be arrays in {path}. File was not changed.")
plugins = [convert_plugin(item) for item in [*legacy_plugins, *native_plugins]]
plugins = [
    item for item in plugins
    if not (
        plugin_spec(item) == learn_plugin_spec
        or plugin_spec(item) == learn_legacy_plugin_base
        or plugin_spec(item).startswith(f"{learn_legacy_plugin_base}#")
        or plugin_spec(item) == learn_older_plugin_base
        or plugin_spec(item).startswith(f"{learn_older_plugin_base}#")
        or plugin_spec(item) == plannotator_plugin_spec
    )
]
plugins.append({
    "package": plannotator_plugin_spec,
    "options": {"workflow": "plan-agent", "planningAgents": ["plan"]},
})
deduplicated = []
seen = set()
for item in plugins:
    spec = plugin_spec(item)
    if spec not in seen:
        seen.add(spec)
        deduplicated.append(item)
data["plugins"] = deduplicated

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
native_servers = mcp.get("servers", {})
if not isinstance(native_servers, dict):
    raise SystemExit(f"ERROR: Expected 'mcp.servers' to be an object in {path}. File was not changed.")
servers = {}
for name, config in mcp.items():
    if name in {"servers", "timeout"}:
        continue
    if not isinstance(config, dict):
        raise SystemExit(f"ERROR: Expected 'mcp.{name}' to be an object in {path}. File was not changed.")
    config = dict(config)
    if "disabled" not in config and "enabled" in config:
        config["disabled"] = not bool(config.pop("enabled"))
    else:
        config.pop("enabled", None)
    if isinstance(config.get("timeout"), int):
        timeout = config["timeout"]
        config["timeout"] = {"catalog": timeout, "execution": timeout}
    servers[name] = config
for name, config in native_servers.items():
    if not isinstance(config, dict):
        raise SystemExit(f"ERROR: Expected 'mcp.servers.{name}' to be an object in {path}. File was not changed.")
    servers[name] = dict(config)
servers.pop("open-design", None)
for name, url in remote_mcps.items():
    servers[name] = {"type": "remote", "url": url, "disabled": False}
ai_memory = {
    "type": "remote",
    "url": f"{ai_memory_server_url}/mcp",
    "disabled": False,
}
token_path = os.path.expanduser(ai_memory_auth_token_reference.replace("~", "~", 1))
if ai_memory_server_url != "http://127.0.0.1:49374" or (os.path.isfile(token_path) and os.path.getsize(token_path) > 0):
    ai_memory["headers"] = {"Authorization": f"Bearer {{file:{ai_memory_auth_token_reference}}}"}
servers["ai-memory"] = ai_memory
servers["github"] = {
    "type": "remote",
    "url": "https://api.githubcopilot.com/mcp/",
    "disabled": False,
    "oauth": False,
    "headers": {
        "Authorization": f"Bearer {{file:{github_mcp_token_reference}}}",
        "X-MCP-Toolsets": "context,repos,issues,pull_requests,actions",
    },
}
data["mcp"] = {"servers": servers}

compaction = data.get("compaction", {})
if not isinstance(compaction, dict):
    raise SystemExit(f"ERROR: Expected 'compaction' to be an object in {path}. File was not changed.")
if "keep" not in compaction and "preserve_recent_tokens" in compaction:
    compaction["keep"] = {"tokens": compaction.pop("preserve_recent_tokens")}
else:
    compaction.pop("preserve_recent_tokens", None)
if "buffer" not in compaction and "reserved" in compaction:
    compaction["buffer"] = compaction.pop("reserved")
else:
    compaction.pop("reserved", None)
compaction.pop("tail_turns", None)
compaction.pop("prune", None)
compaction["auto"] = False
data["compaction"] = compaction

skills = data.get("skills", [])
if isinstance(skills, dict):
    skills = [*skills.get("paths", []), *skills.get("urls", [])]
if not isinstance(skills, list) or not all(isinstance(item, str) for item in skills):
    raise SystemExit(f"ERROR: Expected 'skills' to be an array in {path}. File was not changed.")
skills = [item for item in skills if "/open-design/" not in item]

data["skills"] = list(dict.fromkeys(skills))

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

merge_opencode_cli_json() {
  log "Merging OpenCode V2 cli.json"

  local config="$HOME/.config/opencode/cli.json"
  mkdir -p "$(dirname "$config")"

  python3 - \
    "$config" \
    "$HOME/.config/opencode/tui.json" \
    "$HOME/.config/opencode/tui.jsonc" \
    "$OPENCODE_TUI_THEME" <<'PY' || return 1
import json
import os
import sys

path = sys.argv[1]
tui_paths = sys.argv[2:4]
theme_name = sys.argv[4]
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

if not data:
    for tui_path in tui_paths:
        if not os.path.exists(tui_path):
            continue
        try:
            with open(tui_path, "r", encoding="utf-8") as f:
                legacy = json.load(f)
        except json.JSONDecodeError as exc:
            raise SystemExit(f"ERROR: Invalid JSON in {tui_path}: {exc}. File was not changed.")
        if not isinstance(legacy, dict):
            raise SystemExit(f"ERROR: Expected an object in {tui_path}. File was not changed.")
        if isinstance(legacy.get("theme"), str):
            data.setdefault("theme", {"name": legacy["theme"]})
        if isinstance(legacy.get("keybinds"), dict):
            data.setdefault("keybinds", {}).update(legacy["keybinds"])
        break

data["$schema"] = "https://opencode.ai/v2/cli.json"
theme = data.get("theme", {})
if isinstance(theme, str):
    theme = {"name": theme}
if not isinstance(theme, dict):
    raise SystemExit(f"ERROR: Expected 'theme' to be an object in {path}. File was not changed.")
theme["name"] = theme_name
data["theme"] = theme

keybinds = data.get("keybinds", {})
if not isinstance(keybinds, dict):
    raise SystemExit(
        f"ERROR: Expected 'keybinds' to be an object in {path}. "
        "File was not changed."
    )

keybinds["session.sidebar.toggle"] = "ctrl+b"
keybinds["session.background"] = False
keybinds["input.move.left"] = "left"
data["keybinds"] = keybinds

data.pop("plugin", None)
plugins = data.get("plugins", [])
if not isinstance(plugins, list):
    raise SystemExit(f"ERROR: Expected 'plugins' to be an array in {path}. File was not changed.")
data["plugins"] = plugins

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY

  rm -f "$HOME/.config/opencode/tui.json" "$HOME/.config/opencode/tui.jsonc"
}

remove_v1_opencode_plugins() {
  local plugin
  log "Removing V1-only generated OpenCode plugins"
  for plugin in \
    "$HOME/.config/opencode/plugins/ai-memory.ts" \
    "$HOME/.config/opencode/plugins/rtk.ts" \
    "$HOME/.config/opencode/plugins/herdr-agent-state.js"
  do
    [[ ! -e "$plugin" && ! -L "$plugin" ]] || rm -f "$plugin"
  done
}

setup_opencode() {
  copy_agents_md
  ensure_github_mcp_token_file
  python3 "$AGENT_STACK_HELPER" ensure-private-file "$AI_MEMORY_AUTH_TOKEN_FILE" "ai-memory client token path"
  merge_opencode_json
  install_opencode_themes
  merge_opencode_cli_json
  remove_v1_opencode_plugins
}

ensure_ai_memory_env_file() {
  log "Preparing the machine-local ai-memory environment file"

  python3 "$AGENT_STACK_HELPER" \
    ensure-private-file \
    "$AI_MEMORY_ENV_FILE" \
    "ai-memory environment path"
}

ai_memory_env_value() {
  local name="$1"

  python3 "$AGENT_STACK_HELPER" env-value "$AI_MEMORY_ENV_FILE" "$name"
}

ai_memory_env_has_nonempty_value() {
  local name="$1"
  local value

  value="$(ai_memory_env_value "$name" 2>/dev/null)" || return 1
  [[ -n "$value" ]]
}

# Pause-flag ownership: agents owns AGENTS_AI_MEMORY_LLM_ENABLED. The
# DOTFILES_ name is retired; read it as fallback for one release so existing
# checkouts migrate without losing an explicit false.
ai_memory_llm_enabled() {
  local value
  value="$(ai_memory_env_value AGENTS_AI_MEMORY_LLM_ENABLED 2>/dev/null || true)"
  if [[ -z "$value" ]]; then
    value="$(ai_memory_env_value DOTFILES_AI_MEMORY_LLM_ENABLED 2>/dev/null || true)"
  fi
  [[ "$value" != "false" ]]
}

ai_memory_profile_list() {
  printf '%s\n' \
    opencode-go-deepseek-v4.1-flash \
    opencode-go-muse-spark-1.3-contributor
}

ai_memory_profile_spec() {
  case "$1" in
    opencode-go-muse-spark-1.3-contributor)
      printf '%s\n' 'opencode|muse-spark-1.3-contributor|opencode-api-key|opencode-go/muse-spark-1.3-contributor'
      ;;
    opencode-go-deepseek-v4.1-flash)
      printf '%s\n' 'opencode|deepseek-v4.1-flash|opencode-api-key|opencode-go/deepseek-v4.1-flash'
      ;;
    *)
      return 1
      ;;
  esac
}

opencode_subagent_profile_list() {
  ai_memory_profile_list
}

# The one profile the whole stack follows: the ai-memory LLM, the OpenCode
# subagents, and the title agent all resolve from this single value. Three
# separate selectors let them drift apart, which is how agents.title ended up
# holding a model id that no profile has ever produced.
agent_stack_is_client_host() {
  [[ "$AI_MEMORY_SERVER_URL" != "$AI_MEMORY_LOOPBACK_SERVER_URL" ]]
}

# A client host runs no services and holds no store, so its sessions execute on
# the server and the server owns the profile. The client deliberately does not
# carry a copy: a stale copy is worse than none, because it looks authoritative.
agent_stack_profile_owner_note() {
  log "Profile selection is owned by the server host. This host carries no profile."
  log "  A session here runs on the server, so the server's opencode.json and"
  log "  ai-memory environment decide the model. Change it there, not here."
}

opencode_subagent_profile_model() {
  ai_memory_profile_spec "$1" | cut -d'|' -f4
}

ai_memory_selected_profile() {
  local profile supported

  profile="$(ai_memory_env_value DOTFILES_AI_MEMORY_LLM_PROFILE 2>/dev/null || true)"
  profile="${profile:-$AI_MEMORY_DEFAULT_LLM_PROFILE}"
  if ! ai_memory_profile_spec "$profile" >/dev/null; then
    supported="$(ai_memory_profile_list | paste -sd, - | sed 's/,/, /g')"
    die "Unsupported DOTFILES_AI_MEMORY_LLM_PROFILE '$profile'. Supported profiles: $supported. Remove the assignment to use the default."
  fi
  printf '%s\n' "$profile"
}

ai_memory_profile_credential_ready() {
  case "$1" in
    opencode-api-key)
      ai_memory_env_has_nonempty_value OPENCODE_API_KEY
      ;;
    *)
      return 1
      ;;
  esac
}

configure_ai_memory_env_file() {
  local profile profile_spec provider model credential subagent_model provider_state
  ensure_ai_memory_env_file
  log "Converging the ai-memory provider and paid-job policy"

  # A client runs no ai-memory service, so the server owns the profile and the
  # provider choice. Strip the values a client inherits rather than
  # leave inert ones behind: a value that governs nothing still reads as live.
  if agent_stack_is_client_host; then
    provider_state="$(python3 - \
      "$AI_MEMORY_ENV_FILE" \
      "$AGENT_STACK_HELPER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
helper_path = Path(sys.argv[2])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text, parse_env_assignment

# Owned by the server host. Never written on a client.
server_owned = {
    "DOTFILES_AI_MEMORY_LLM_PROFILE",
    "AI_MEMORY_LLM_PROVIDER",
    "AI_MEMORY_LLM_MODEL",
}
# Retired selectors, removed on every host so no dead variable lingers.
retired = {"DOTFILES_OPENCODE_SUBAGENT_PROFILE"}
# Retired pause flag: migrate its value once to the agents-owned name.
retired_pause_old = "DOTFILES_AI_MEMORY_LLM_ENABLED"
retired_pause_new = "AGENTS_AI_MEMORY_LLM_ENABLED"
# Stale marker from the dotfiles-era installer; current apply.sh never wrote
# it, so drop it wherever it still heads a block.
stale_comments = {"# Managed by dotfiles/agents/apply.sh."}
# Managed here as well, so every copy is stripped before one is appended.
client_managed = {"AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL"}
managed_comment = "# Managed by guisaliba/agents apply.sh."

try:
    original_lines = path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read ai-memory environment file at {path}: {exc}")

pause_value = None
pause_new_present = False
for line in original_lines:
    parsed = parse_env_assignment(line)
    if parsed is None:
        continue
    if parsed[0] == retired_pause_new:
        pause_new_present = True
    if parsed[0] == retired_pause_old:
        pause_value = parsed[1]

kept_lines = []
for line in original_lines:
    if line == managed_comment:
        continue
    if line in stale_comments:
        continue
    parsed = parse_env_assignment(line)
    if parsed is not None and parsed[0] in server_owned:
        continue
    if parsed is not None and parsed[0] in retired:
        continue
    if parsed is not None and parsed[0] == retired_pause_old:
        continue
    # Strip names this branch owns too, so a copy written by an earlier run or
    # left above the marker cannot survive alongside the one appended below.
    if parsed is not None and parsed[0] in client_managed:
        continue
    kept_lines.append(line)

if pause_value is not None and not pause_new_present:
    kept_lines.append(f"{retired_pause_new}={pause_value}")

while kept_lines and not kept_lines[-1].strip():
    kept_lines.pop()
if kept_lines:
    kept_lines.append("")

kept_lines.extend(
    [
        managed_comment,
        "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=true",
    ]
)

content = "\n".join(kept_lines) + "\n"
atomic_write_text(path, content, 0o600, ".env.")
print("client")
PY
)" || die "Could not clear the server-owned ai-memory policy for a client host"
    agent_stack_profile_owner_note
    return 0
  fi

  profile="$(ai_memory_selected_profile)" || return 1
  profile_spec="$(ai_memory_profile_spec "$profile")"
  IFS='|' read -r provider model credential subagent_model <<<"$profile_spec"

  provider_state="zero-llm"
  if ai_memory_llm_enabled && ai_memory_profile_credential_ready "$credential"; then
    provider_state="enabled"
  else
    provider=""
  fi

  provider_state="$(python3 - \
    "$AI_MEMORY_ENV_FILE" \
    "$profile" \
    "$provider" \
    "$model" \
    "$provider_state" \
    "$AGENT_STACK_HELPER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
profile = sys.argv[2]
provider = sys.argv[3]
model = sys.argv[4]
provider_state = sys.argv[5]
helper_path = Path(sys.argv[6])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text, parse_env_assignment

managed_names = {
    "DOTFILES_AI_MEMORY_LLM_PROFILE",
    "AI_MEMORY_LLM_PROVIDER",
    "AI_MEMORY_LLM_MODEL",
    "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL",
}
# The scheduler flag is the operator's, not the script's. It is written as a
# literal "false" here today, which makes a value in the environment file look
# editable while every apply.sh run silently reverts it. That is the same defect
# class as the path translation and the client token: a setting that appears to
# be configured but is actually owned elsewhere. Read it instead, so an explicit
# operator value survives.
operator_owned_names = {"AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED"}
scheduler_default = "false"
managed_comment = "# Managed by guisaliba/agents apply.sh."
# Retired pause flag: migrate its value once to the agents-owned name.
retired_pause_old = "DOTFILES_AI_MEMORY_LLM_ENABLED"
retired_pause_new = "AGENTS_AI_MEMORY_LLM_ENABLED"
# Stale marker from the dotfiles-era installer; current apply.sh never wrote
# it, so drop it wherever it still heads a block.
stale_comments = {"# Managed by dotfiles/agents/apply.sh."}


try:
    original_lines = path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read ai-memory environment file at {path}: {exc}")

# Last assignment wins, matching the shared parser, so read the operator's value
# before removing every copy of the name.
scheduler_value = None
pause_value = None
pause_new_present = False
for line in original_lines:
    parsed = parse_env_assignment(line)
    if parsed is None:
        continue
    name, value = parsed
    if name in operator_owned_names:
        scheduler_value = value
    if name == retired_pause_new:
        pause_new_present = True
    if name == retired_pause_old:
        pause_value = value
if scheduler_value is None:
    scheduler_value = scheduler_default

kept_lines = []
for line in original_lines:
    if line == managed_comment:
        continue
    if line in stale_comments:
        continue
    parsed = parse_env_assignment(line)
    if parsed is not None and parsed[0] in managed_names:
        continue
    if parsed is not None and parsed[0] in operator_owned_names:
        continue
    if parsed is not None and parsed[0] == retired_pause_old:
        continue
    kept_lines.append(line)

while kept_lines and not kept_lines[-1].strip():
    kept_lines.pop()
if kept_lines:
    kept_lines.append("")

# The operator's own value goes above the managed block, so the ownership split
# stays visible: everything above the marker is theirs, everything below is ours.
kept_lines.append(f"AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED={scheduler_value}")
if pause_value is not None and not pause_new_present:
    kept_lines.append(f"{retired_pause_new}={pause_value}")
kept_lines.append("")
kept_lines.extend(
    [
        managed_comment,
        f"DOTFILES_AI_MEMORY_LLM_PROFILE={profile}",
        "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=true",
        f"AI_MEMORY_LLM_PROVIDER={provider}",
        f"AI_MEMORY_LLM_MODEL={model}",
    ]
)

content = "\n".join(kept_lines) + "\n"
atomic_write_text(path, content, 0o600, ".env.")

print(provider_state)
PY
)" || die "Could not configure the ai-memory provider policy"

  if [[ "$provider_state" == "enabled" ]]; then
    log "ai-memory LLM enabled by $profile"
  elif ! ai_memory_llm_enabled; then
    log "ai-memory LLM paused by AGENTS_AI_MEMORY_LLM_ENABLED=false"
  elif [[ "$credential" == "opencode-api-key" ]]; then
    log "ai-memory remains in zero-LLM mode. Add OPENCODE_API_KEY to $AI_MEMORY_ENV_FILE, then rerun apply."
  fi
}

initialize_ai_memory() {
  log "Initializing the ai-memory user data layout"

  python3 "$AGENT_STACK_HELPER" \
    guard-regular-file \
    "$AI_MEMORY_CONFIG_FILE" \
    "ai-memory config path"

  mkdir -p "$AI_MEMORY_DATA_DIR" "$(dirname "$AI_MEMORY_CONFIG_FILE")"
  ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    init || die "ai-memory initialization failed"

  chmod 700 "$AI_MEMORY_DATA_DIR" "$(dirname "$AI_MEMORY_CONFIG_FILE")"
  chmod 600 "$AI_MEMORY_CONFIG_FILE"

  configure_ai_memory_env_file
}

install_ai_memory_systemd_user_service() {
  local executable
  executable="$(type -P ai-memory)" || \
    die "ai-memory must resolve to an executable file on PATH"

  log "Installing the managed ai-memory user service"
  python3 "$AGENT_STACK_HELPER" \
    guard-regular-file \
    "$AI_MEMORY_USER_SERVICE_FILE" \
    "ai-memory user service path"
  mkdir -p "$(dirname "$AI_MEMORY_USER_SERVICE_FILE")"

  python3 - \
    "$AI_MEMORY_USER_SERVICE_FILE" \
    "$executable" \
    "$AGENT_STACK_HELPER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
executable = str(Path(sys.argv[2]).absolute())
helper_path = Path(sys.argv[3])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text


def systemd_quote(value):
    escaped = value.replace("\\", "\\\\").replace('"', '\\"').replace("%", "%%")
    return f'"{escaped}"'


content = "\n".join(
    [
        "# Managed by guisaliba/agents apply.sh.",
        "[Unit]",
        "Description=ai-memory MCP server (user service)",
        "Documentation=https://github.com/akitaonrails/ai-memory",
        "",
        "[Service]",
        "Type=simple",
        "EnvironmentFile=-%h/.config/ai-memory/env",
        (
            f"ExecStart={systemd_quote(executable)} "
            "--data-dir %h/.local/share/ai-memory "
            "--config %h/.config/ai-memory/config.toml "
            "serve --transport http --enable-web"
        ),
        "Restart=on-failure",
        "RestartSec=5s",
        "NoNewPrivileges=true",
        "PrivateTmp=true",
        "",
        "[Install]",
        "WantedBy=default.target",
        "",
    ]
)

try:
    if path.read_text(encoding="utf-8") == content:
        raise SystemExit(0)
except FileNotFoundError:
    pass
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read ai-memory user service at {path}: {exc}")

atomic_write_text(path, content, 0o644, ".ai-memory.service.")
PY
}

install_ai_memory_launch_daemon() {
  local executable username group
  executable="$(type -P ai-memory)" || \
    die "ai-memory must resolve to an executable file on PATH"
  username="$(id -un)" || die "Could not resolve the current user name"
  group="$(id -gn)" || die "Could not resolve the current user group"

  log "Generating the managed ai-memory LaunchDaemon source"
  python3 "$AGENT_STACK_HELPER" \
    guard-regular-file \
    "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE" \
    "ai-memory LaunchDaemon source path"
  mkdir -p "$(dirname "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE")" "$AI_MEMORY_LAUNCH_DAEMON_LOG_DIR"
  chmod 700 "$AI_MEMORY_LAUNCH_DAEMON_LOG_DIR"
  touch \
    "$AI_MEMORY_LAUNCH_DAEMON_LOG_DIR/stdout.log" \
    "$AI_MEMORY_LAUNCH_DAEMON_LOG_DIR/stderr.log"
  chmod 600 \
    "$AI_MEMORY_LAUNCH_DAEMON_LOG_DIR/stdout.log" \
    "$AI_MEMORY_LAUNCH_DAEMON_LOG_DIR/stderr.log"

  python3 - \
    "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE" \
    "$executable" \
    "$AGENT_STACK_HELPER" \
    "$HOME" \
    "$AI_MEMORY_LAUNCH_DAEMON_LABEL" \
    "$username" \
    "$group" <<'PY'
import plistlib
import sys
from pathlib import Path

path = Path(sys.argv[1])
executable = str(Path(sys.argv[2]).absolute())
helper_path = Path(sys.argv[3])
home = sys.argv[4]
label = sys.argv[5]
username = sys.argv[6]
group = sys.argv[7]
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text


config = {
    "Label": label,
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
content = plistlib.dumps(config, fmt=plistlib.FMT_XML, sort_keys=False).decode("utf-8")

try:
    if path.read_text(encoding="utf-8") == content:
        raise SystemExit(0)
except FileNotFoundError:
    pass
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read ai-memory LaunchDaemon source at {path}: {exc}")

atomic_write_text(path, content, 0o600, ".ai-memory-launch-daemon.")
PY
  chmod 600 "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE"
}

install_ai_memory_user_service() {
  case "$(agent_stack_platform)" in
    Linux) install_ai_memory_systemd_user_service ;;
    Darwin) install_ai_memory_launch_daemon ;;
  esac
}

start_ai_memory_systemd_user_service() {
  log "Enabling and restarting the ai-memory user service"

  install_ai_memory_systemd_user_service
  systemctl --user daemon-reload || die "systemd user daemon reload failed"
  systemctl --user enable ai-memory.service || die "ai-memory user service enablement failed"
  systemctl --user restart ai-memory.service || die "ai-memory user service restart failed"
}

start_ai_memory_launch_daemon() {
  local target installed_contract
  target="system/$AI_MEMORY_LAUNCH_DAEMON_LABEL"

  log "Verifying the ai-memory LaunchDaemon"
  install_ai_memory_launch_daemon
  installed_contract="$(stat -f '%Su:%Sg:%Lp' "$AI_MEMORY_LAUNCH_DAEMON_FILE" 2>/dev/null || true)"
  if [[ ! -f "$AI_MEMORY_LAUNCH_DAEMON_FILE" ]] || \
    [[ "$installed_contract" != "root:wheel:644" ]] || \
    ! cmp -s "$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE" "$AI_MEMORY_LAUNCH_DAEMON_FILE"; then
    die "ai-memory LaunchDaemon requires privileged installation. Run these commands:
launchctl bootout 'gui/$(id -u)/$AI_MEMORY_LAUNCH_AGENT_LABEL' >/dev/null 2>&1 || true
sudo launchctl bootout '$target' >/dev/null 2>&1 || true
sudo install -o root -g wheel -m 0644 '$AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE' '$AI_MEMORY_LAUNCH_DAEMON_FILE'
sudo launchctl bootstrap system '$AI_MEMORY_LAUNCH_DAEMON_FILE'
sudo launchctl kickstart -k '$target'"
  fi
  if ! launchctl print "$target" >/dev/null 2>&1; then
    die "ai-memory LaunchDaemon is installed but inactive. Run these commands:
launchctl bootout 'gui/$(id -u)/$AI_MEMORY_LAUNCH_AGENT_LABEL' >/dev/null 2>&1 || true
sudo launchctl bootstrap system '$AI_MEMORY_LAUNCH_DAEMON_FILE'
sudo launchctl kickstart -k '$target'"
  fi
  if [[ -e "$AI_MEMORY_LAUNCH_AGENT_FILE" || -L "$AI_MEMORY_LAUNCH_AGENT_FILE" ]]; then
    launchctl bootout "gui/$(id -u)/$AI_MEMORY_LAUNCH_AGENT_LABEL" >/dev/null 2>&1 || true
    rm -f "$AI_MEMORY_LAUNCH_AGENT_FILE"
  fi
}

start_ai_memory_service() {
  case "$(agent_stack_platform)" in
    Linux) start_ai_memory_systemd_user_service ;;
    Darwin) start_ai_memory_launch_daemon ;;
  esac
}

warn_on_stale_ai_memory_service() {
  # The macOS LaunchDaemon is only bootstrapped when it is absent or inactive,
  # so a healthy service is never restarted and never re-reads
  # ~/.config/ai-memory/env. A configuration change can therefore sit in the
  # file for ever while the process keeps running the old values, and nothing
  # reports the divergence. Linux restarts unconditionally, so it cannot drift.
  [[ "$(agent_stack_platform)" == "Darwin" ]] || return 0
  [[ -f "$AI_MEMORY_ENV_FILE" ]] || return 0

  python3 - \
    "$AI_MEMORY_ENV_FILE" \
    "$AI_MEMORY_LAUNCH_DAEMON_LABEL" \
    "$AGENT_STACK_HELPER" <<'PY'
import os
import subprocess
import sys
from pathlib import Path

env_path = Path(sys.argv[1])
label = sys.argv[2]
helper_path = Path(sys.argv[3])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import parse_env_assignment


def launchctl(*arguments):
    try:
        result = subprocess.run(
            ["launchctl", *arguments],
            capture_output=True,
            text=True,
            timeout=20,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout


# A stopped service is not a stale one. Report the difference honestly instead
# of implying the running configuration is out of date.
printed = launchctl("print", f"system/{label}")
if printed is None:
    sys.exit(0)
pid = None
for line in printed.splitlines():
    stripped = line.strip()
    if stripped.startswith("pid ="):
        pid = stripped.split("=", 1)[1].strip()
        break
if not pid:
    sys.exit(0)

try:
    environment_output = subprocess.run(
        ["ps", "eww", "-p", pid],
        capture_output=True,
        text=True,
        timeout=20,
    )
except (OSError, subprocess.SubprocessError):
    sys.exit(0)
if environment_output.returncode != 0:
    sys.exit(0)

# The service execs through a shell that sources the environment file, so the
# file-injected variables are present in the process environment. Read it as
# flat assignments rather than as a launchd plist, which shows only what
# launchd itself supplied.
running = {}
for token in environment_output.stdout.split():
    name, separator, value = token.partition("=")
    if separator and name:
        running.setdefault(name, value)

stale = []
for line in env_path.read_text(encoding="utf-8").splitlines():
    parsed = parse_env_assignment(line)
    if parsed is None:
        continue
    name, value = parsed
    if name not in running:
        # Not exported into the process, so there is nothing to compare.
        continue
    if running[name] != value:
        stale.append(name)

if not stale:
    sys.exit(0)

print()
print("WARNING: the running ai-memory service is stale.")
print(f"    Service : system/{label} (pid {pid})")
print(f"    Env file: {env_path}")
print("    Changed : " + ", ".join(sorted(stale)))
print("    The service execs through a shell that sourced the environment file")
print("    once at start, so it is still running the previous values. Restart it:")
print(f"      sudo launchctl kickstart -k system/{label}")
print("    This is a warning on purpose. apply.sh did not restart the service,")
print("    because that needs an interactive sudo.")
print()
PY
}

wire_ai_memory_to_opencode() {
  log "Installing the ai-memory OpenCode V2 lifecycle plugin"
  # The token is required whenever the server enforces bearer authentication,
  # which includes a loopback host that also runs the OpenCode server. Key the
  # decision off the token file, not off the server URL, so the two agree.
  local auth_token_arguments=()
  if [[ -s "$AI_MEMORY_AUTH_TOKEN_FILE" ]]; then
    auth_token_arguments=(--auth-token "$(<"$AI_MEMORY_AUTH_TOKEN_FILE")")
  fi
  ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    install-hooks \
    --agent opencode2 \
    --server-url "$AI_MEMORY_SERVER_URL" \
    --project-strategy repo-root \
    "${auth_token_arguments[@]}" \
    --apply || die "ai-memory OpenCode V2 hook installation failed"
  chmod 600 "$HOME/.config/opencode/plugins/ai-memory-opencode2.ts"

  log "Generating current ai-memory routing instructions"
  ai-memory install-instructions \
    --target "$HOME/.config/opencode/AGENTS.md" \
    --no-skills || die "ai-memory instruction installation failed"

  log "Installing current ai-memory Agent Skills"
  ai-memory install-skills \
    --scope global \
    --agent agents || die "ai-memory skill installation failed"
}

setup_ai_memory() {
  if [[ "$AI_MEMORY_SERVER_URL" == "$AI_MEMORY_LOOPBACK_SERVER_URL" ]]; then
    initialize_ai_memory
    start_ai_memory_service
  else
    log "Using centralized ai-memory at $AI_MEMORY_SERVER_URL"
    # A client still needs its environment file converged, because it carries
    # the server URL and the scheduler flag. This also strips the policy the
    # server owns, which would otherwise linger as a value that governs nothing.
    configure_ai_memory_env_file
    if [[ "$(agent_stack_platform)" == Linux ]]; then
      systemctl --user disable --now ai-memory.service >/dev/null 2>&1 || true
    fi
  fi
  wire_ai_memory_to_opencode
}

install_rtk() {
  if have rtk; then
    log "RTK already installed, skipping"
  else
    log "Installing RTK"
    curl -fsSL "https://raw.githubusercontent.com/rtk-ai/rtk/$RTK_VERSION/install.sh" | \
      RTK_VERSION="$RTK_VERSION" sh || die "RTK install failed"
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
  log "Installing V2-compatible plugins"
  log "RTK is disabled: no released RTK version has verified OpenCode V2 support"
  install_plannotator
}

install_skill() {
  local source="$1"
  local name="$2"
  log "Installing/updating skill: $name"

  npx -y skills add "$source" -g -a opencode -s "$name" -y --copy </dev/null || \
    die "Failed to install skill: $name"
}

install_manifest_skill() {
  local requested_name="$1"
  local manifest_rows provider name source_ref require_skill_file found=false

  manifest_rows="$(python3 "$AGENT_STACK_HELPER" manifest "$SKILLS_MANIFEST")" || \
    die "Could not read the required skill manifest"
  while IFS=$'\t' read -r provider name source_ref require_skill_file; do
    if [[ "$name" != "$requested_name" ]]; then
      continue
    fi
    case "$provider" in
      local)
        install_local_skill "$REPO_DIR/$source_ref" "$name"
        ;;
      upstream)
        install_skill "$source_ref" "$name"
        ;;
      *)
        die "Skill $name is owned by its dedicated $provider installer"
        ;;
    esac
    found=true
  done <<<"$manifest_rows"

  [[ "$found" == true ]] || die "Required skill is not in $SKILLS_MANIFEST: $requested_name"
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

remove_legacy_alvar_skills() {
  local name
  log "Removing retired Alvar skills"
  for name in learn-profile learn-verify learn-visual probe teach; do
    rm -rf "$HOME/.agents/skills/$name"
  done
}


install_cloudflare_skills() {
  log "Installing/updating Cloudflare skills"
  npx -y skills add https://github.com/cloudflare/skills -g -a opencode -y --copy </dev/null || \
    die "Cloudflare skills install failed"
}

install_required_skills() {
  local manifest_rows provider name source_ref require_skill_file

  log "Installing/updating required skills"

  mkdir -p "$HOME/.agents/skills"
  remove_legacy_alvar_skills

  manifest_rows="$(python3 "$AGENT_STACK_HELPER" manifest "$SKILLS_MANIFEST")" || \
    die "Could not read the required skill manifest"

  while IFS=$'\t' read -r provider name source_ref require_skill_file; do
    case "$provider" in
      local)
        install_local_skill "$REPO_DIR/$source_ref" "$name"
        ;;
      upstream)
        install_skill "$source_ref" "$name"
        ;;
    esac
  done <<<"$manifest_rows"

  install_cloudflare_skills
}

main() {
  log "Starting OpenCode agent stack setup"

  prepare_platform_prerequisites
  prepare_full_stack_prerequisites
  check_prerequisites
  require_minimum_version bun "$BUN_MIN_VERSION"
  install_opencode
  install_ai_memory
  report_optional_ai_jail
  verify_ai_memory_unauthenticated_loopback
  setup_opencode
  setup_ai_memory
  warn_on_stale_ai_memory_service
  start_opencode_server
  merge_opencode_shell_override
  configure_bash_login_env
  install_plugins
  install_required_skills

  log "Setup complete. Open a new Bash shell or source ~/.bash_aliases, then run ./test.sh to verify."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
