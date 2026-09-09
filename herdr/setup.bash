#!/usr/bin/env bash

# Sourceable Herdr setup functions. This file does not run setup when sourced.

HERDR_SETUP_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HERDR_REPO_DIR="$(cd -- "$HERDR_SETUP_DIR/.." && pwd)"
HERDR_AGENT_STACK_HELPER="$HERDR_REPO_DIR/lib/agent_stack.py"
HERDR_RELEASE_VERSION="0.9.0"
HERDR_RELEASE_BASE_URL="https://github.com/herdrdev/herdr/releases/download/v$HERDR_RELEASE_VERSION"
HERDR_X86_64_SHA256="4fa1a01158dd8043da92d31b270780b0dcc10603038d9b61cac4d81ab63fb71f"
HERDR_AARCH64_SHA256="9c8db20fb7e7427b138d5367113f1621ffd319f2f65d6f009e2594029115f0d2"
HERDR_MACOS_X86_64_SHA256="f3b231b2815df9a62f98e060751c29bdacdc6f26761be813d08918c8080e51aa"
HERDR_MACOS_AARCH64_SHA256="32b53df09872628059c789a69f02a6b8e29e14ddf26711421f3463f70c1aef17"
HERDR_INSTALL_DIR="${HERDR_INSTALL_DIR:-$HOME/.local/bin}"
HERDR_BINARY="${HERDR_BINARY:-$HERDR_INSTALL_DIR/herdr}"
HERDR_BACKUP_ROOT="${HERDR_BACKUP_ROOT:-$HOME/.local/state/agents/herdr/backups}"
HERDR_CONFIG_FILE="${HERDR_CONFIG_FILE:-$HOME/.config/herdr/config.toml}"
HERDR_OPENCODE_DIR="${HERDR_OPENCODE_DIR:-$HOME/.config/opencode}"
HERDR_OPENCODE_PLUGIN="$HERDR_OPENCODE_DIR/plugins/herdr-agent-state.js"
HERDR_OPENCODE_TUI_PLUGIN="$HERDR_OPENCODE_DIR/herdr-tui-session.js"
HERDR_OPENCODE_TUI_CONFIG="$HERDR_OPENCODE_DIR/tui.jsonc"
HERDR_OPENCODE_INTEGRATION_VERSION="11"

herdr_log() {
  printf '\n==> %s\n' "$*"
}

herdr_error() {
  printf 'ERROR: %s\n' "$*" >&2
  return 1
}

check_herdr_prerequisites() {
  local command_name missing=()
  for command_name in bash curl python3; do
    if ! command -v "$command_name" >/dev/null 2>&1; then
      missing+=("$command_name")
    fi
  done
  if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    missing+=("sha256sum or shasum")
  fi
  if [[ ${#missing[@]} -gt 0 ]]; then
    herdr_error "Missing Herdr setup prerequisites: ${missing[*]}."
    return 1
  fi
  python3 -c 'import tomllib' >/dev/null 2>&1 || {
    herdr_error "Python 3.11 or newer is required for safe Herdr TOML configuration."
    return 1
  }
}

herdr_release_spec() {
  local system architecture os_kind

  system="$(uname -s)" || return 1
  architecture="$(uname -m)" || return 1
  os_kind="$(uname -o 2>/dev/null || true)"

  if [[ "$os_kind" == Android* || -n "${ANDROID_ROOT:-}" || -n "${ANDROID_DATA:-}" || "${PREFIX:-}" == /data/data/com.termux/* ]]; then
    herdr_error "Herdr $HERDR_RELEASE_VERSION does not support Android or Termux."
    return 1
  fi
  case "$system:$architecture" in
    Linux:x86_64)
      printf '%s\t%s\n' "herdr-linux-x86_64" "$HERDR_X86_64_SHA256"
      ;;
    Linux:aarch64|Linux:arm64)
      printf '%s\t%s\n' "herdr-linux-aarch64" "$HERDR_AARCH64_SHA256"
      ;;
    Darwin:x86_64)
      printf '%s\t%s\n' "herdr-macos-x86_64" "$HERDR_MACOS_X86_64_SHA256"
      ;;
    Darwin:aarch64|Darwin:arm64)
      printf '%s\t%s\n' "herdr-macos-aarch64" "$HERDR_MACOS_AARCH64_SHA256"
      ;;
    Linux:*|Darwin:*)
      herdr_error "Herdr $HERDR_RELEASE_VERSION does not support $system architecture $architecture."
      return 1
      ;;
    *)
      herdr_error "Herdr $HERDR_RELEASE_VERSION setup supports Linux and macOS only (found $system)."
      return 1
      ;;
  esac
}

herdr_binary_version() {
  local executable="$1" output
  output="$("$executable" --version 2>/dev/null)" || return 1
  if [[ "$output" =~ ^herdr[[:space:]]+([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

herdr_sha256() {
  local output
  if command -v sha256sum >/dev/null 2>&1; then
    output="$(sha256sum "$1")" || return 1
  else
    output="$(shasum -a 256 "$1")" || return 1
  fi
  printf '%s\n' "${output%%[[:space:]]*}"
}

herdr_version_is_newer() {
  local actual="$1" expected="$2"
  local actual_major actual_minor actual_patch expected_major expected_minor expected_patch
  IFS=. read -r actual_major actual_minor actual_patch <<<"$actual"
  IFS=. read -r expected_major expected_minor expected_patch <<<"$expected"

  if (( actual_major != expected_major )); then
    (( actual_major > expected_major ))
  elif (( actual_minor != expected_minor )); then
    (( actual_minor > expected_minor ))
  else
    (( actual_patch > expected_patch ))
  fi
}

backup_herdr_binary() {
  local timestamp backup_dir suffix=0
  timestamp="$(date -u +%Y%m%dT%H%M%SZ)" || return 1
  backup_dir="$HERDR_BACKUP_ROOT/$timestamp"
  while [[ -e "$backup_dir" ]]; do
    suffix=$((suffix + 1))
    backup_dir="$HERDR_BACKUP_ROOT/$timestamp-$suffix"
  done
  mkdir -p "$backup_dir"
  cp -p "$HERDR_BINARY" "$backup_dir/herdr"
  printf '%s\n' "$backup_dir/herdr"
}

install_herdr_binary() {
  local release_spec asset expected_sha existing_command installed_version
  local download_url temporary_file actual_sha downloaded_version backup_path
  local replace_existing=false

  release_spec="$(herdr_release_spec)" || return 1
  IFS=$'\t' read -r asset expected_sha <<<"$release_spec"

  if [[ -L "$HERDR_BINARY" ]]; then
    herdr_error "Herdr managed path must not be a symlink: $HERDR_BINARY"
    return 1
  fi
  if [[ -e "$HERDR_BINARY" && ! -f "$HERDR_BINARY" ]]; then
    herdr_error "Herdr managed path must be a regular file: $HERDR_BINARY"
    return 1
  fi

  existing_command="$(type -P herdr 2>/dev/null || true)"
  if [[ -n "$existing_command" && "$existing_command" != "$HERDR_BINARY" ]]; then
    herdr_error "Herdr already resolves to an unmanaged or package-managed executable at $existing_command; $HERDR_BINARY was not installed."
    return 1
  fi

  if [[ -f "$HERDR_BINARY" ]]; then
    installed_version="$(herdr_binary_version "$HERDR_BINARY" || true)"
    if [[ "$installed_version" == "$HERDR_RELEASE_VERSION" ]]; then
      actual_sha="$(herdr_sha256 "$HERDR_BINARY")" || {
        herdr_error "Could not verify the existing Herdr executable at $HERDR_BINARY."
        return 1
      }
      if [[ "$actual_sha" != "$expected_sha" ]]; then
        herdr_error "Herdr $HERDR_RELEASE_VERSION at $HERDR_BINARY does not match the pinned release digest."
        return 1
      fi
      herdr_log "Herdr $HERDR_RELEASE_VERSION is already installed at $HERDR_BINARY"
      return 0
    fi
    if [[ -z "$installed_version" ]]; then
      herdr_error "Herdr at $HERDR_BINARY has an unreadable version; it was not replaced."
      return 1
    fi
    if herdr_version_is_newer "$installed_version" "$HERDR_RELEASE_VERSION"; then
      herdr_error "Herdr $installed_version at $HERDR_BINARY is newer than pinned version $HERDR_RELEASE_VERSION; it was not downgraded."
      return 1
    fi
    replace_existing=true
  fi

  mkdir -p "$HERDR_INSTALL_DIR"
  (
    temporary_file="$(mktemp "$HERDR_INSTALL_DIR/.herdr.$HERDR_RELEASE_VERSION.XXXXXX")" || exit 1
    trap '[[ -z "$temporary_file" ]] || rm -f -- "$temporary_file"' EXIT
    download_url="$HERDR_RELEASE_BASE_URL/$asset"
    if ! curl --fail --location --silent --show-error --output "$temporary_file" "$download_url"; then
      herdr_error "Could not download Herdr $HERDR_RELEASE_VERSION from $download_url."
      exit 1
    fi

    actual_sha="$(herdr_sha256 "$temporary_file")" || {
      herdr_error "Could not calculate the Herdr download digest."
      exit 1
    }
    if [[ "$actual_sha" != "$expected_sha" ]]; then
      herdr_error "Herdr download digest did not match the pinned $asset release."
      exit 1
    fi

    chmod 755 "$temporary_file" || {
      herdr_error "Could not make the verified Herdr download executable."
      exit 1
    }
    downloaded_version="$(herdr_binary_version "$temporary_file" || true)"
    if [[ "$downloaded_version" != "$HERDR_RELEASE_VERSION" ]]; then
      herdr_error "Downloaded Herdr reports version ${downloaded_version:-unknown}; expected $HERDR_RELEASE_VERSION."
      exit 1
    fi

    if [[ "$replace_existing" == true ]]; then
      backup_path="$(backup_herdr_binary)" || {
        herdr_error "Could not back up the existing Herdr executable; it was not replaced."
        exit 1
      }
      herdr_log "Saved the previous Herdr executable at $backup_path"
    fi

    mv -f "$temporary_file" "$HERDR_BINARY" || {
      herdr_error "Could not atomically install Herdr at $HERDR_BINARY."
      exit 1
    }
    temporary_file=""
    herdr_log "Installed Herdr $HERDR_RELEASE_VERSION at $HERDR_BINARY"
  )
}

configure_herdr() {
  local bash_command bash_path shell_mode="non_login"
  bash_command="$(type -P bash 2>/dev/null)" || {
    herdr_error "Bash is required for Herdr panes."
    return 1
  }
  bash_path="$(python3 - "$bash_command" <<'PY'
import sys
from pathlib import Path

try:
    print(Path(sys.argv[1]).resolve(strict=True))
except OSError:
    raise SystemExit(1)
PY
  )" || {
    herdr_error "Could not resolve the Bash executable at $bash_command."
    return 1
  }
  if [[ "$(uname -s)" == Darwin ]]; then
    shell_mode="login"
  fi
  if [[ "$bash_path" != /* || ! -f "$bash_path" || ! -x "$bash_path" ]]; then
    herdr_error "Herdr pane shell is not an executable regular file: $bash_path"
    return 1
  fi

  python3 "$HERDR_AGENT_STACK_HELPER" \
    guard-regular-file \
    "$HERDR_CONFIG_FILE" \
    "Herdr config path" || return 1

  python3 - \
    "$HERDR_CONFIG_FILE" \
    "$bash_path" \
    "$shell_mode" \
    "$HERDR_AGENT_STACK_HELPER" <<'PY'
import json
import re
import stat
import sys
import tomllib
from pathlib import Path

path = Path(sys.argv[1])
bash_path = sys.argv[2]
shell_mode = sys.argv[3]
helper_path = Path(sys.argv[4])
sys.path.insert(0, str(helper_path.parent))
sys.dont_write_bytecode = True

from agent_stack import atomic_write_text

managed = {
    "terminal": {
        "default_shell": json.dumps(bash_path),
        "shell_mode": json.dumps(shell_mode),
    },
    "session": {
        "resume_agents_on_restore": "false",
    },
}
expected_types = {
    ("terminal", "default_shell"): str,
    ("terminal", "shell_mode"): str,
    ("session", "resume_agents_on_restore"): bool,
}
table_header = re.compile(r"^\s*\[([^\[\]]+)\]\s*(?:#.*)?$")


def inline_comment(line):
    quote = None
    escaped = False
    for index, character in enumerate(line):
        if quote == '"':
            if escaped:
                escaped = False
            elif character == "\\":
                escaped = True
            elif character == '"':
                quote = None
            continue
        if quote == "'":
            if character == "'":
                quote = None
            continue
        if character in {'"', "'"}:
            quote = character
        elif character == "#":
            return line[index:]
    return None

try:
    original = path.read_text(encoding="utf-8") if path.exists() else ""
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
except OSError as exc:
    raise SystemExit(f"ERROR: Cannot read Herdr config at {path}: {exc}")

try:
    parsed = tomllib.loads(original)
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(f"ERROR: Expected valid Herdr TOML at {path}: {exc}. File was not changed.")

for table_name, assignments in managed.items():
    table_value = parsed.get(table_name)
    if table_value is not None and not isinstance(table_value, dict):
        raise SystemExit(
            f"ERROR: Herdr {table_name} must be a table in {path}. File was not changed."
        )
    if isinstance(table_value, dict):
        for key in assignments:
            value = table_value.get(key)
            expected_type = expected_types[(table_name, key)]
            if value is not None and type(value) is not expected_type:
                raise SystemExit(
                    f"ERROR: Herdr {table_name}.{key} has an incompatible value in {path}. "
                    "File was not changed."
                )

lines = original.splitlines()
sections = {}
current = None
for index, line in enumerate(lines):
    match = table_header.match(line)
    if match is None:
        continue
    current = match.group(1).strip()
    if current in managed:
        if current in sections:
            raise SystemExit(
                f"ERROR: Herdr [{current}] appears more than once in {path}. File was not changed."
            )
        sections[current] = [index, len(lines)]
    for section_name, bounds in sections.items():
        if section_name != current and bounds[1] == len(lines):
            bounds[1] = index

for table_name in managed:
    if table_name in parsed and table_name not in sections:
        raise SystemExit(
            f"ERROR: Herdr {table_name} must use a [{table_name}] table in {path}. "
            "File was not changed."
        )

for table_name, (start, end) in sorted(
    sections.items(), key=lambda item: item[1][0], reverse=True
):
    assignments = managed[table_name]
    body = lines[start + 1 : end]
    kept = []
    found = {key: 0 for key in assignments}
    for line in body:
        matched_key = None
        for key in assignments:
            key_pattern = rf"^\s*(?:{re.escape(key)}|\"{re.escape(key)}\"|'{re.escape(key)}')\s*="
            if re.match(key_pattern, line):
                matched_key = key
                break
        if matched_key is None:
            kept.append(line)
            continue
        found[matched_key] += 1
        if '"""' in line or "'''" in line:
            raise SystemExit(
                f"ERROR: Herdr {table_name}.{matched_key} must use a one-line value in {path}. "
                "File was not changed."
            )
        comment = inline_comment(line)
        if comment is not None:
            kept.append(comment)

    table_value = parsed.get(table_name, {})
    for key in assignments:
        if key in table_value and found[key] != 1:
            raise SystemExit(
                f"ERROR: Could not safely locate Herdr {table_name}.{key} in {path}. "
                "File was not changed."
            )

    while kept and not kept[-1].strip():
        kept.pop()
    if kept:
        kept.append("")
    kept.extend(f"{key} = {value}" for key, value in assignments.items())
    lines[start + 1 : end] = kept

for table_name, assignments in managed.items():
    if table_name in sections:
        continue
    while lines and not lines[-1].strip():
        lines.pop()
    if lines:
        lines.append("")
    lines.append(f"[{table_name}]")
    lines.extend(f"{key} = {value}" for key, value in assignments.items())

content = "\n".join(lines) + "\n"
try:
    tomllib.loads(content)
except tomllib.TOMLDecodeError as exc:
    raise SystemExit(
        f"ERROR: Refusing to write invalid merged Herdr TOML at {path}: {exc}"
    )

if content == original:
    raise SystemExit(0)

path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
atomic_write_text(path, content, mode, ".herdr-config.")
PY
}

install_herdr_opencode_integration() {
  local status line current=false file content

  if [[ ! -x "$HERDR_BINARY" ]]; then
    herdr_error "Herdr executable is missing or is not executable: $HERDR_BINARY"
    return 1
  fi
  if [[ -L "$HERDR_OPENCODE_DIR" || ! -d "$HERDR_OPENCODE_DIR" ]]; then
    herdr_error "OpenCode config directory must be an existing regular directory: $HERDR_OPENCODE_DIR"
    return 1
  fi
  if [[ -L "$HERDR_OPENCODE_DIR/plugins" ]]; then
    herdr_error "OpenCode plugin directory must not be a symlink: $HERDR_OPENCODE_DIR/plugins"
    return 1
  fi
  for file in \
    "$HERDR_OPENCODE_PLUGIN" \
    "$HERDR_OPENCODE_TUI_PLUGIN" \
    "$HERDR_OPENCODE_TUI_CONFIG"
  do
    python3 "$HERDR_AGENT_STACK_HELPER" guard-regular-file "$file" "Herdr OpenCode integration path" || return 1
  done

  herdr_log "Installing the official Herdr OpenCode integration"
  "$HERDR_BINARY" integration install opencode || {
    herdr_error "Herdr could not install the OpenCode integration."
    return 1
  }
  status="$("$HERDR_BINARY" integration status)" || {
    herdr_error "Herdr could not report integration status."
    return 1
  }
  printf '%s\n' "$status"
  while IFS= read -r line; do
    if [[ "$line" == "opencode: current (v$HERDR_OPENCODE_INTEGRATION_VERSION) ("* ]]; then
      current=true
      break
    fi
  done <<<"$status"
  if [[ "$current" != true ]]; then
    herdr_error "Herdr OpenCode integration is not current at integration version $HERDR_OPENCODE_INTEGRATION_VERSION."
    return 1
  fi

  if [[ ! -f "$HERDR_OPENCODE_TUI_CONFIG" || -L "$HERDR_OPENCODE_TUI_CONFIG" ]] || \
    ! python3 - "$HERDR_OPENCODE_TUI_CONFIG" <<'PY'
import sys
from pathlib import Path

content = Path(sys.argv[1]).read_text(encoding="utf-8")
raise SystemExit(0 if content.count("./herdr-tui-session.js") == 1 else 1)
PY
  then
    herdr_error "Herdr OpenCode TUI config must contain exactly one Herdr plugin entry: $HERDR_OPENCODE_TUI_CONFIG"
    return 1
  fi

  for file in "$HERDR_OPENCODE_PLUGIN" "$HERDR_OPENCODE_TUI_PLUGIN"; do
    if [[ ! -f "$file" || -L "$file" ]]; then
      herdr_error "Herdr OpenCode integration component is missing or unsafe: $file"
      return 1
    fi
    content="$(<"$file")"
    if [[ "$content" != *"HERDR_INTEGRATION_VERSION=$HERDR_OPENCODE_INTEGRATION_VERSION"* ]]; then
      herdr_error "Herdr OpenCode integration component has the wrong version: $file"
      return 1
    fi
  done
}

setup_herdr() {
  check_herdr_prerequisites
  install_herdr_binary
  configure_herdr
  install_herdr_opencode_integration
}
