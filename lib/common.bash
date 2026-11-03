# shellcheck shell=bash
# lib/common.bash
#
# Shared logging, platform, prerequisite, and version helpers for apply.sh.
# Sourced by apply.sh. Do not execute directly.

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
      ;;
    *) die "Unsupported operating system: $(agent_stack_platform)" ;;
  esac
}


check_prerequisites() {
  log "Checking prerequisites"
  local cmd platform missing=()
  local commands=(bash curl git python3)
  platform="$(agent_stack_platform)"
  case "$platform" in
    # bwrap and socat: the Claude Code sandbox for read-only worker seats.
    Linux) commands+=(systemctl bwrap socat) ;;
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
  local minimum_version="${3:-}"

  if have "$command_name"; then
    if [[ -z "$minimum_version" ]] || \
      (require_minimum_version "$command_name" "$minimum_version") >/dev/null 2>&1; then
      log "$command_name already meets its minimum version, skipping"
      return
    fi
    log "Updating $command_name to version $minimum_version from the AUR"
  else
    log "Installing $command_name from the AUR package $package_name"
  fi

  have yay || die "$command_name is missing or too old. Install or update $package_name with an AUR helper, or put a supported native $command_name binary on PATH before running apply."

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

