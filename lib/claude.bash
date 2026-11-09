# shellcheck shell=bash
# lib/claude.bash
#
# Claude Code installation, the main (Claude Pro) profile, the pstack plugin,
# the pstack worker profile, and the Bash entry points.
# Sourced by apply.sh. Do not execute directly.

install_claude_code() {
  if ! type -P claude >/dev/null 2>&1; then
    log "Installing Claude Code with the native installer"
    curl -fsSL "$CLAUDE_INSTALL_URL" | bash || die "Claude Code installation failed"
    prepend_path "$HOME/.local/bin"
    type -P claude >/dev/null 2>&1 || die "Claude Code installation did not put claude on PATH"
  fi

  if ! (require_minimum_version claude "$CLAUDE_MIN_VERSION") >/dev/null 2>&1; then
    log "Updating Claude Code to $CLAUDE_MIN_VERSION or newer"
    claude update || die "claude update failed"
  fi
  require_minimum_version claude "$CLAUDE_MIN_VERSION"
  log "Claude Code $(claude --version 2>/dev/null)"
}

install_managed_file() {
  local source="$1" target="$2" label="$3"

  [[ -f "$source" ]] || die "Missing managed source for $label: $source"
  python3 "$AGENT_STACK_HELPER" guard-regular-file "$target" "$label"
  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && cmp -s "$source" "$target"; then
    return 0
  fi
  if [[ -f "$target" ]]; then
    local backup
    backup="$target.bak-$(date -u +%Y%m%dT%H%M%SZ)"
    cp -p "$target" "$backup" || die "Could not back up $target before replacing it"
    log "Backed up the previous $label to $backup"
  fi
  cp "$source" "$target"
  chmod 644 "$target"
}

# RTK expects its import on the last line of the user instructions file.
# The sources do not carry the import: Claude Code would resolve @RTK.md
# relative to the source file, in the repository, where no RTK.md exists.
# apply.sh writes the import into the installed copy, so rtk init finds it
# and does not append a second one, and the next apply sees no change.
install_instructions_file() {
  local source="$1" target="$2" label="$3" generated status=0

  [[ -f "$source" ]] || die "Missing managed source for $label: $source"
  if grep -qx '@RTK.md' "$source"; then
    die "The $label source must not import RTK.md; apply.sh adds the import: $source"
  fi
  generated="$(mktemp)"
  { cat "$source"; printf '\n@RTK.md\n'; } >"$generated"
  install_managed_file "$generated" "$target" "$label" || status=$?
  rm -f -- "$generated"
  return "$status"
}

configure_claude_main_profile() {
  local rule

  log "Installing the global instructions and pstack rules for Claude Code"
  install_instructions_file "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" "Claude Code global instructions"
  for rule in "${CLAUDE_MANAGED_RULES[@]}"; do
    install_managed_file "$REPO_DIR/claude/rules/$rule" "$CLAUDE_RULES_DIR/$rule" "Claude Code rule $rule"
  done

  # Opus is the main model. The allow rules let the coordinator start
  # worker seats without one permission prompt per seat. The built-in
  # you-should-know mod is off by default; it needs a direct claude.ai login,
  # so it is enabled in the main profile only.
  log "Selecting Opus as the main Claude Code model, allowing claude-worker, and enabling you-should-know"
  python3 "$AGENT_STACK_HELPER" merge-json \
    "$CLAUDE_HOME/settings.json" \
    "{\"model\": \"$CLAUDE_MAIN_MODEL\", \"permissions\": {\"allow\": [\"Bash(claude-worker run *)\", \"Bash(claude-worker usage)\", \"Bash(claude-worker models)\"]}, \"enabledPlugins\": {\"$CLAUDE_YOU_SHOULD_KNOW_PLUGIN\": true}}" \
    "Claude Code user settings" || die "Could not update $CLAUDE_HOME/settings.json"
}

install_pstack_plugin() {
  log "Installing or updating the pstack plugin"
  export CLAUDE_CODE_PLUGIN_PREFER_HTTPS=1

  if claude plugin marketplace list 2>/dev/null | grep -q "$PSTACK_MARKETPLACE_NAME"; then
    claude plugin marketplace update "$PSTACK_MARKETPLACE_NAME" || \
      die "Could not update the $PSTACK_MARKETPLACE_NAME marketplace"
  else
    claude plugin marketplace add "$PSTACK_MARKETPLACE_SOURCE" || \
      die "Could not add the $PSTACK_MARKETPLACE_SOURCE marketplace"
  fi

  if claude plugin list 2>/dev/null | grep -q "$PSTACK_PLUGIN"; then
    claude plugin update "$PSTACK_PLUGIN" || die "Could not update $PSTACK_PLUGIN"
  else
    claude plugin install "$PSTACK_PLUGIN" --scope user || die "Could not install $PSTACK_PLUGIN"
  fi
}

worker_provider_setting() {
  local value
  value="$(python3 "$AGENT_STACK_HELPER" env-value "$WORKER_PROVIDER_FILE" "$1")" || \
    die "$1 is missing in $WORKER_PROVIDER_FILE"
  printf '%s\n' "$value"
}

worker_settings_patch() {
  python3 - \
    "$REPO_DIR/bin/claude-worker-key" \
    "$(worker_provider_setting WORKER_ANTHROPIC_BASE_URL)" \
    "$(worker_provider_setting WORKER_BACKGROUND_MODEL)" <<'PY'
import json
import sys

key_helper, base_url, background_model = sys.argv[1:]
print(json.dumps({
    "apiKeyHelper": key_helper,
    "env": {
        "ANTHROPIC_BASE_URL": base_url,
        # Session titles and other background tasks use the haiku slot.
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": background_model,
        # A gateway that forwards to non-Anthropic models rejects
        # pre-release Anthropic request fields.
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    },
}))
PY
}

configure_worker_profile() {
  local link
  local -a commands=(claude-worker claude-worker-key)

  log "Configuring the pstack worker profile in $CLAUDE_WORKER_HOME ($(worker_provider_setting WORKER_PROVIDER))"
  mkdir -p "$CLAUDE_WORKER_HOME"
  chmod 700 "$CLAUDE_WORKER_HOME"
  install_instructions_file "$REPO_DIR/claude/worker/contract.md" "$CLAUDE_WORKER_HOME/CLAUDE.md" "worker instructions"
  python3 "$AGENT_STACK_HELPER" merge-json \
    "$CLAUDE_WORKER_HOME/settings.json" \
    "$(worker_settings_patch)" \
    "worker settings" || die "Could not update $CLAUDE_WORKER_HOME/settings.json"

  log "Linking claude-worker and claude-worker-key into ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  for link in "${commands[@]}"; do
    if [[ -e "$HOME/.local/bin/$link" && ! -L "$HOME/.local/bin/$link" ]]; then
      die "Refusing to replace a file that is not a symlink: $HOME/.local/bin/$link"
    fi
    ln -sfn "$REPO_DIR/bin/$link" "$HOME/.local/bin/$link"
  done

  if ! "$REPO_DIR/bin/claude-worker-key" >/dev/null 2>&1; then
    log "Worker provider API key not found. Run claude-worker-key for the reason before you use worker/ roles."
  fi
}

merge_claude_shell_block() {
  log "Making interactive Bash claude starts use ai-memory managed workstreams"
  # The OpenCode setup that this branch replaces owned this block. Remove it so
  # the retired opencode wrapper no longer loads.
  python3 "$AGENT_STACK_HELPER" remove-block \
    "$BASH_ALIASES_FILE" \
    "$RETIRED_OPENCODE_SHELL_BLOCK_START" "$RETIRED_OPENCODE_SHELL_BLOCK_END" || \
    die "Could not remove the retired OpenCode wrapper block from $BASH_ALIASES_FILE"

  python3 "$AGENT_STACK_HELPER" merge-block \
    "$BASH_ALIASES_SOURCE" "$BASH_ALIASES_FILE" \
    "$CLAUDE_SHELL_BLOCK_START" "$CLAUDE_SHELL_BLOCK_END" || \
    die "Could not merge the Claude Code wrapper block into $BASH_ALIASES_FILE"
}

# Login Bash loads the interactive wrapper and the operator overrides. It does
# not load ~/.config/ai-memory/env: the service reads that file through its
# unit, and claude-worker-key reads the key from it, so no shell needs to
# export the API key.
configure_bash_login_env() {
  log "Making login Bash load the managed shell"
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
        end_marker,
    ]
)
content = "\n".join(kept) + "\n"
if content == text:
    raise SystemExit(0)

atomic_write_text(path, content, mode, ".bash_profile.")
PY
}
