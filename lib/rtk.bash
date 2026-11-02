# shellcheck shell=bash
# lib/rtk.bash
#
# RTK command-line installation and its Claude Code hook.
# install_rtk and its compatibility checks moved unchanged from the OpenCode
# apply.sh. wire_rtk_to_claude_code is the harness-specific function.
# Sourced by apply.sh. Do not execute directly.

rtk_cli_is_compatible() {
  local version_output rewrite_output rewrite_exit probe_home

  version_output="$(rtk --version 2>/dev/null)" || return 1
  python3 - "$version_output" <<'PY' || return 1
import re
import sys

if not re.search(r"(?<!\d)v?\d+\.\d+\.\d+(?![A-Za-z0-9.+-])", sys.argv[1]):
    raise SystemExit(1)
PY

  probe_home="$(mktemp -d)" || return 1
  mkdir -p "$probe_home/.claude" "$probe_home/.config" || {
    rm -rf "$probe_home"
    return 1
  }
  if rewrite_output="$(
    cd "$probe_home" && \
      HOME="$probe_home" \
      XDG_CONFIG_HOME="$probe_home/.config" \
      CLAUDE_CONFIG_DIR="$probe_home/.claude" \
      rtk rewrite 'git status --short' 2>/dev/null
  )"; then
    rewrite_exit=0
  else
    rewrite_exit=$?
  fi
  rm -rf "$probe_home"
  [[ "$rewrite_exit" == 0 || "$rewrite_exit" == 3 ]] || return 1

  rewrite_output="${rewrite_output#"${rewrite_output%%[![:space:]]*}"}"
  rewrite_output="${rewrite_output%"${rewrite_output##*[![:space:]]}"}"
  [[ "$rewrite_output" == 'rtk git status --short' ]]
}

rtk_cli_meets_install_version() {
  local version_output
  version_output="$(rtk --version 2>/dev/null)" || return 1
  python3 - "$RTK_VERSION" "$version_output" <<'PY'
import re
import sys

def version(value):
    match = re.search(r"(?<!\d)v?(\d+)\.(\d+)\.(\d+)(?![A-Za-z0-9.+-])", value)
    return tuple(map(int, match.groups())) if match else None

required = version(sys.argv[1])
installed = version(sys.argv[2])
if required is None or installed is None or installed < required:
    raise SystemExit(1)
PY
}

install_rtk() {
  local install_required=false version_output
  RTK_CLI_INSTALLED_BY_APPLY=false

  if have rtk; then
    if rtk_cli_is_compatible; then
      version_output="$(rtk --version 2>/dev/null)"
      log "Keeping compatible RTK CLI: $version_output"
    else
      log "Installed RTK CLI does not pass the rewrite compatibility check"
      install_required=true
    fi
  else
    install_required=true
  fi

  if [[ "$install_required" == true ]]; then
    [[ "$RTK_VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || \
      die "RTK_VERSION must be a stable vX.Y.Z release tag; branches and prereleases are not allowed"
    log "Installing RTK CLI $RTK_VERSION"
    curl -fsSL "https://raw.githubusercontent.com/rtk-ai/rtk/$RTK_VERSION/install.sh" | \
      RTK_VERSION="$RTK_VERSION" sh || die "RTK install failed"
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
    have rtk || die "RTK install did not put rtk on PATH"
    rtk_cli_is_compatible || die "Installed RTK CLI failed its rewrite compatibility check"
    rtk_cli_meets_install_version || \
      die "Installed RTK CLI is older than the pinned stable release $RTK_VERSION"
    RTK_CLI_INSTALLED_BY_APPLY=true
  fi

  rtk gain || true
}


# Install the RTK PreToolUse hook into one Claude Code configuration directory.
# RTK resolves the directory from CLAUDE_CONFIG_DIR, so the same function wires
# the main profile and the OpenCode Go worker profile. Default mode also writes
# RTK.md and adds an @RTK.md import to that directory's CLAUDE.md, so call this
# after apply.sh writes the managed CLAUDE.md.
wire_rtk_to_claude_code() {
  local config_dir="$1"

  log "Installing the RTK Claude Code hook in $config_dir"
  mkdir -p "$config_dir"
  CLAUDE_CONFIG_DIR="$config_dir" rtk init -g --auto-patch --no-trust-filters </dev/null || \
    die "RTK Claude Code hook installation failed for $config_dir"
}
