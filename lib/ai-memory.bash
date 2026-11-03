# shellcheck shell=bash
# lib/ai-memory.bash
#
# Native ai-memory installation, per-host service, and environment policy.
# The functions in this file are harness-independent. They moved unchanged from
# the OpenCode apply.sh, except for the removed OpenCode server-host branch.
# wire_ai_memory_to_claude_code is the only harness-specific function.
# Sourced by apply.sh. Do not execute directly.

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
  local existing_command installed_version managed_release_root temporary_link

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
    die "Managed macOS ai-memory symlink must target a versioned release under $managed_release_root"
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
      if have ai-memory; then
        verify_native_ai_memory
      fi
      install_aur_command ai-memory "$AI_MEMORY_AUR_PACKAGE" "$AI_MEMORY_MIN_VERSION"
      ;;
    Darwin) install_ai_memory_macos ;;
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

  # A host pointed at a remote ai-memory server uses remote-client policy. The
  # ai-memory CLI reads its bearer from the environment, so it must be allowed.
  if agent_stack_uses_remote_ai_memory; then
    log "Verifying the authenticated ai-memory client policy for $AI_MEMORY_SERVER_URL"
    if [[ -z "${AI_MEMORY_AUTH_TOKEN:-}" ]] && \
      ! ai_memory_env_has_nonempty_value AI_MEMORY_AUTH_TOKEN && \
      [[ ! -s "$AI_MEMORY_AUTH_TOKEN_FILE" ]]; then
      die "Remote ai-memory mode requires a bearer token for $AI_MEMORY_SERVER_URL. Put one in $AI_MEMORY_AUTH_TOKEN_FILE, or export AI_MEMORY_AUTH_TOKEN, then re-run apply."
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


ai_memory_server_url_is_loopback() {
  python3 - "$AI_MEMORY_SERVER_URL" <<'PY'
import ipaddress
import sys
from urllib.parse import urlsplit

try:
    url = urlsplit(sys.argv[1])
    host = url.hostname
    url.port  # Validate the optional port instead of accepting malformed URLs.
except ValueError:
    raise SystemExit(2)

if url.scheme not in {"http", "https"} or not host or url.username or url.password:
    raise SystemExit(2)

host = host.rstrip(".").lower()
if host == "localhost" or host.endswith(".localhost"):
    raise SystemExit(0)

try:
    address = ipaddress.ip_address(host)
except ValueError:
    raise SystemExit(1)

if isinstance(address, ipaddress.IPv6Address) and address.ipv4_mapped is not None:
    address = address.ipv4_mapped
raise SystemExit(0 if address.is_loopback else 1)
PY
}

agent_stack_uses_remote_ai_memory() {
  local loopback_status=0
  ai_memory_server_url_is_loopback || loopback_status=$?
  case "$loopback_status" in
    0) return 1 ;;
    1) return 0 ;;
    *) die "AI_MEMORY_SERVER_URL must be a valid HTTP(S) URL without user information" ;;
  esac
}

# A host that uses a remote ai-memory service has no local store, so the remote
# server owns its profile. Do not carry a stale local copy that looks authoritative.
agent_stack_profile_owner_note() {
  log "Profile selection is owned by the remote ai-memory server. This host carries no profile."
  log "  The remote server's ai-memory environment decides the model."
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

  # A host using a remote ai-memory service does not own its profile or provider
  # choice. Strip those values rather than leave inert settings that look live.
  if agent_stack_uses_remote_ai_memory; then
    provider_state="$(python3 - \
      "$AI_MEMORY_ENV_FILE" \
      "$AGENT_STACK_HELPER" \
      "$AI_MEMORY_SERVER_URL" <<'PY'
import shlex
import sys
from pathlib import Path

path = Path(sys.argv[1])
helper_path = Path(sys.argv[2])
server_url = sys.argv[3]
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
client_managed = {
    "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL",
    "AI_MEMORY_SERVER_URL",
    "AGENTS_AI_MEMORY_REMOTE_MODE",
}
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
        f"AI_MEMORY_SERVER_URL={shlex.quote(server_url)}",
        "AGENTS_AI_MEMORY_REMOTE_MODE=true",
        "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=true",
    ]
)

content = "\n".join(kept_lines) + "\n"
atomic_write_text(path, content, 0o600, ".env.")
print("client")
PY
  )" || die "Could not clear the remote-service ai-memory policy for this host"
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
    "$AI_MEMORY_SERVER_URL" \
    "$AGENT_STACK_HELPER" <<'PY'
import shlex
import sys
from pathlib import Path

path = Path(sys.argv[1])
profile = sys.argv[2]
provider = sys.argv[3]
model = sys.argv[4]
provider_state = sys.argv[5]
server_url = sys.argv[6]
helper_path = Path(sys.argv[7])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text, parse_env_assignment

managed_names = {
    "DOTFILES_AI_MEMORY_LLM_PROFILE",
    "AI_MEMORY_LLM_PROVIDER",
    "AI_MEMORY_LLM_MODEL",
    "AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL",
    "AI_MEMORY_SERVER_URL",
    "AGENTS_AI_MEMORY_REMOTE_MODE",
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
        f"AI_MEMORY_SERVER_URL={shlex.quote(server_url)}",
        "AGENTS_AI_MEMORY_REMOTE_MODE=false",
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


# Wire ai-memory into the main Claude Code profile only. The pstack worker
# profile ($CLAUDE_WORKER_HOME) never receives these hooks, so worker runs do
# not write observations into the coordinator's workstream.
wire_ai_memory_to_claude_code() {
  local auth_token_arguments=() auth_token=""

  if agent_stack_uses_remote_ai_memory; then
    auth_token="${AI_MEMORY_AUTH_TOKEN:-}"
    if [[ -z "$auth_token" && -s "$AI_MEMORY_AUTH_TOKEN_FILE" ]]; then
      auth_token="$(<"$AI_MEMORY_AUTH_TOKEN_FILE")"
    fi
  fi
  if [[ -n "$auth_token" ]]; then
    auth_token_arguments=(--auth-token "$auth_token")
  fi

  log "Installing the ai-memory Claude Code lifecycle hooks"
  env -u CLAUDE_CONFIG_DIR ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    install-hooks \
    --agent claude-code \
    --server-url "$AI_MEMORY_SERVER_URL" \
    --project-strategy repo-root \
    "${auth_token_arguments[@]}" \
    --apply || die "ai-memory Claude Code hook installation failed"

  log "Registering the ai-memory MCP server for Claude Code"
  env -u CLAUDE_CONFIG_DIR ai-memory \
    --data-dir "$AI_MEMORY_DATA_DIR" \
    --config "$AI_MEMORY_CONFIG_FILE" \
    install-mcp \
    --client claude-code \
    --server-url "$AI_MEMORY_SERVER_URL" \
    "${auth_token_arguments[@]}" \
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
  if ! agent_stack_uses_remote_ai_memory; then
    initialize_ai_memory
    start_ai_memory_service
  else
    log "Using remote ai-memory at $AI_MEMORY_SERVER_URL"
    # A client still needs its environment file converged, because it carries
    # the server URL and the scheduler flag. This also strips the policy the
    # server owns, which would otherwise linger as a value that governs nothing.
    configure_ai_memory_env_file
    if [[ "$(agent_stack_platform)" == Linux ]]; then
      systemctl --user disable --now ai-memory.service >/dev/null 2>&1 || true
    fi
  fi
  wire_ai_memory_to_claude_code
}
