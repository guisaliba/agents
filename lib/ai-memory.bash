# shellcheck shell=bash
# lib/ai-memory.bash
#
# Native ai-memory installation, per-host service, and environment policy.
# The functions in this file are harness-independent. They moved unchanged from
# the OpenCode apply.sh, except for the removed OpenCode server-host branch.
# wire_ai_memory_to_claude_code is the only harness-specific function.
# Sourced by apply.sh. Do not execute directly.

# Print the operating system and machine of this host, tab-separated.
ai_memory_platform() {
  printf '%s\t%s\n' "$(agent_stack_platform)" "$(uname -m)"
}

# Print the release asset and its pinned SHA256 for this host.
ai_memory_release_spec() {
  local platform machine
  IFS=$'\t' read -r platform machine <<<"$(ai_memory_platform)"
  case "$platform/$machine" in
    Darwin/arm64|Darwin/aarch64)
      printf '%s\t%s\n' "ai-memory-macos-aarch64.tar.gz" "$AI_MEMORY_MACOS_AARCH64_SHA256" ;;
    Darwin/x86_64)
      printf '%s\t%s\n' "ai-memory-macos-x86_64.tar.gz" "$AI_MEMORY_MACOS_X86_64_SHA256" ;;
    Linux/aarch64|Linux/arm64)
      printf '%s\t%s\n' "ai-memory-linux-aarch64.tar.gz" "$AI_MEMORY_LINUX_AARCH64_SHA256" ;;
    Linux/x86_64)
      printf '%s\t%s\n' "ai-memory-linux-x86_64.tar.gz" "$AI_MEMORY_LINUX_X86_64_SHA256" ;;
    *)
      die "ai-memory $AI_MEMORY_RELEASE_VERSION has no release for $platform $machine" ;;
  esac
}

# Install the pinned upstream release bundle under $AI_MEMORY_INSTALL_ROOT and
# link $AI_MEMORY_BINARY to it. The bundle keeps hooks/claude-code next to
# the binary, where `ai-memory install-hooks` finds it through the symlink.
# Used on macOS, and on Linux hosts without an AUR helper (Ubuntu, WSL2).
install_ai_memory_release() {
  local release_spec asset expected_sha download_url archive temporary_dir actual_sha
  local existing_command installed_version managed_release_root temporary_link

  release_spec="$(ai_memory_release_spec)"
  IFS=$'\t' read -r asset expected_sha <<<"$release_spec"
  download_url="$AI_MEMORY_RELEASE_BASE_URL/$asset"

  existing_command="$(type -P ai-memory 2>/dev/null || true)"
  if [[ -n "$existing_command" && "$existing_command" != "$AI_MEMORY_BINARY" ]]; then
    die "ai-memory already resolves to an unmanaged executable at $existing_command; $AI_MEMORY_BINARY was not installed."
  fi
  if [[ -e "$AI_MEMORY_BINARY" && ! -L "$AI_MEMORY_BINARY" ]]; then
    die "Managed ai-memory path must be a symlink to the release bundle: $AI_MEMORY_BINARY. Remove it and run apply again."
  fi
  managed_release_root="${AI_MEMORY_INSTALL_ROOT%/*}"
  if [[ -L "$AI_MEMORY_BINARY" ]] && ! python3 - \
    "$AI_MEMORY_BINARY" "$managed_release_root" <<'PY'
import sys
from pathlib import Path

binary = Path(sys.argv[1])
release_root = Path(sys.argv[2]).resolve()
try:
    target = binary.resolve(strict=True)
    relative = target.relative_to(release_root)
except (OSError, ValueError):
    raise SystemExit(1)
raise SystemExit(0 if len(relative.parts) == 2 and relative.name == "ai-memory" else 1)
PY
  then
    die "Managed ai-memory symlink must target a versioned release under $managed_release_root"
  fi

  if [[ -d "$AI_MEMORY_INSTALL_ROOT" ]]; then
    [[ -x "$AI_MEMORY_INSTALL_ROOT/ai-memory" ]] || \
      die "Existing ai-memory release bundle is incomplete: $AI_MEMORY_INSTALL_ROOT"
    [[ -d "$AI_MEMORY_INSTALL_ROOT/hooks/claude-code" ]] || \
      die "Existing ai-memory release bundle has no Claude Code hooks: $AI_MEMORY_INSTALL_ROOT"
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
      [[ -d "$temporary_dir/hooks/claude-code" ]] || die "ai-memory release archive has no Claude Code hooks"
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
  [[ -d "$AI_MEMORY_INSTALL_ROOT/hooks/claude-code" ]] || \
    die "Installed ai-memory release bundle has no Claude Code hooks: $AI_MEMORY_INSTALL_ROOT"
  mkdir -p "$(dirname "$AI_MEMORY_BINARY")"
  if [[ -L "$AI_MEMORY_BINARY" ]]; then
    if [[ "$(readlink "$AI_MEMORY_BINARY")" != "$AI_MEMORY_INSTALL_ROOT/ai-memory" ]]; then
      temporary_link="$AI_MEMORY_BINARY.tmp.$$"
      [[ ! -e "$temporary_link" && ! -L "$temporary_link" ]] || \
        die "Temporary ai-memory symlink path already exists: $temporary_link"
      ln -s "$AI_MEMORY_INSTALL_ROOT/ai-memory" "$temporary_link" || \
        die "Could not create temporary ai-memory symlink: $temporary_link"
      if ! mv -f "$temporary_link" "$AI_MEMORY_BINARY"; then
        rm -f "$temporary_link"
        die "Could not switch ai-memory to release $AI_MEMORY_RELEASE_VERSION"
      fi
      log "Updated managed ai-memory symlink to release $AI_MEMORY_RELEASE_VERSION"
    fi
  else
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
    Linux)
      # Arch (yay) and package-managed installs keep the AUR path. Other
      # Linux hosts get the release bundle, which carries the hooks.
      local existing
      existing="$(type -P ai-memory 2>/dev/null || true)"
      if have yay || [[ -n "$existing" && "$existing" != "$AI_MEMORY_BINARY" ]]; then
        if [[ -n "$existing" ]]; then
          verify_native_ai_memory
        fi
        install_aur_command ai-memory "$AI_MEMORY_AUR_PACKAGE" "$AI_MEMORY_MIN_VERSION"
      else
        install_ai_memory_release
      fi
      ;;
    Darwin) install_ai_memory_release ;;
    *) die "Unsupported operating system: $(agent_stack_platform)" ;;
  esac
  verify_native_ai_memory
  require_minimum_version ai-memory "$AI_MEMORY_MIN_VERSION"
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


ensure_ai_memory_env_file() {
  log "Preparing the machine-local ai-memory environment file"

  python3 "$AGENT_STACK_HELPER" \
    ensure-private-file \
    "$AI_MEMORY_ENV_FILE" \
    "ai-memory environment path"
}

check_ai_memory_env_file() {
  ensure_ai_memory_env_file
  log "Checking the ai-memory LLM settings"

  # The operator owns every line of the environment file. apply.sh reads it
  # and reports; it never rewrites it.
  python3 - "$AI_MEMORY_ENV_FILE" "$AGENT_STACK_HELPER" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
helper_path = Path(sys.argv[2])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import parse_env_assignment

# Names that earlier versions of apply.sh wrote. Nothing reads them now.
retired = {
    "AGENTS_AI_MEMORY_LLM_ENABLED",
    "AGENTS_AI_MEMORY_REMOTE_MODE",
    "AI_MEMORY_SERVER_URL",
    "DOTFILES_AI_MEMORY_LLM_ENABLED",
    "DOTFILES_AI_MEMORY_LLM_PROFILE",
    "DOTFILES_OPENCODE_SUBAGENT_PROFILE",
}
# ai-memory reads the key of each provider from its own variable.
provider_keys = {"opencode": "OPENCODE_API_KEY"}

try:
    lines = path.read_text(encoding="utf-8").splitlines()
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read ai-memory environment file at {path}: {exc}")

values = {}
for line in lines:
    parsed = parse_env_assignment(line)
    if parsed is not None:
        values[parsed[0]] = parsed[1].strip()

stale = sorted(name for name in retired if name in values)
if stale:
    print(f"WARNING: {path} sets retired names that nothing reads: {', '.join(stale)}. Remove them.")

provider = values.get("AI_MEMORY_LLM_PROVIDER", "")
model = values.get("AI_MEMORY_LLM_MODEL", "")
missing = [
    name
    for name, value in (("AI_MEMORY_LLM_PROVIDER", provider), ("AI_MEMORY_LLM_MODEL", model))
    if not value
]
key_name = provider_keys.get(provider)
if key_name and not values.get(key_name):
    missing.append(key_name)

if missing:
    verb = "is" if len(missing) == 1 else "are"
    print(f"ai-memory LLM disabled: {', '.join(missing)} {verb} not set in {path}")
else:
    print(f"ai-memory LLM enabled: provider {provider}, model {model}")
PY
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

  check_ai_memory_env_file
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


# Wire ai-memory into the main Claude Code profile only. The pstack worker
# profile ($CLAUDE_WORKER_HOME) never receives these hooks, so worker runs do
# not write observations into the coordinator's workstream.
wire_ai_memory_to_claude_code() {
  log "Installing the ai-memory Claude Code lifecycle hooks"
  env -u CLAUDE_CONFIG_DIR ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    install-hooks \
    --agent claude-code \
    --server-url "$AI_MEMORY_SERVER_URL" \
    --project-strategy repo-root \
    --apply || die "ai-memory Claude Code hook installation failed"

  log "Registering the ai-memory MCP server for Claude Code"
  env -u CLAUDE_CONFIG_DIR ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    install-mcp \
    --client claude-code \
    --server-url "$AI_MEMORY_SERVER_URL" \
    --apply || die "ai-memory Claude Code MCP registration failed"

  log "Generating current ai-memory routing instructions"
  mkdir -p "$CLAUDE_RULES_DIR"
  env -u CLAUDE_CONFIG_DIR ai-memory install-instructions \
    --target "$AI_MEMORY_INSTRUCTIONS_FILE" \
    --no-skills || die "ai-memory instruction installation failed"

  log "Installing current ai-memory Agent Skills for Claude Code"
  env -u CLAUDE_CONFIG_DIR ai-memory install-skills \
    --scope global \
    --agent claude-code || die "ai-memory skill installation failed"
}

setup_ai_memory() {
  initialize_ai_memory
  start_ai_memory_service
  wire_ai_memory_to_claude_code
}
