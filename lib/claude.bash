# shellcheck shell=bash
# lib/claude.bash
#
# Claude Code installation, the main (Claude Pro) profile, the pstack plugin,
# the OpenCode Go worker profile, skills, and the Bash entry points.
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
  cp "$source" "$target"
  chmod 644 "$target"
}

configure_claude_main_profile() {
  local rule

  log "Installing the global instructions and pstack rules for Claude Code"
  install_managed_file "$REPO_DIR/CLAUDE.md" "$CLAUDE_HOME/CLAUDE.md" "Claude Code global instructions"
  for rule in "${CLAUDE_MANAGED_RULES[@]}"; do
    install_managed_file "$REPO_DIR/claude/rules/$rule" "$CLAUDE_RULES_DIR/$rule" "Claude Code rule $rule"
  done

  # Opus is the main model. The allow rules let the coordinator start
  # OpenCode Go worker seats without one permission prompt per seat.
  log "Selecting Opus as the main Claude Code model and allowing go-worker"
  python3 "$AGENT_STACK_HELPER" merge-json \
    "$CLAUDE_HOME/settings.json" \
    "{\"model\": \"$CLAUDE_MAIN_MODEL\", \"permissions\": {\"allow\": [\"Bash(go-worker run *)\", \"Bash(go-worker usage)\", \"Bash(go-worker models)\"]}}" \
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

go_worker_settings_patch() {
  python3 - "$REPO_DIR/bin/go-key" "$GO_ANTHROPIC_BASE_URL" "$GO_BACKGROUND_MODEL" <<'PY'
import json
import sys

key_helper, base_url, background_model = sys.argv[1:]
print(json.dumps({
    "apiKeyHelper": key_helper,
    "env": {
        "ANTHROPIC_BASE_URL": base_url,
        # Session titles and other background tasks use the haiku slot.
        "ANTHROPIC_DEFAULT_HAIKU_MODEL": background_model,
        # OpenCode Go forwards to non-Anthropic models that reject
        # pre-release Anthropic request fields.
        "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
        "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    },
}))
PY
}

configure_go_worker_profile() {
  local link="$HOME/.local/bin/go-worker"

  log "Configuring the OpenCode Go worker profile in $CLAUDE_GO_HOME"
  mkdir -p "$CLAUDE_GO_HOME"
  chmod 700 "$CLAUDE_GO_HOME"
  install_managed_file "$REPO_DIR/claude/worker/CLAUDE.md" "$CLAUDE_GO_HOME/CLAUDE.md" "worker instructions"
  python3 "$AGENT_STACK_HELPER" merge-json \
    "$CLAUDE_GO_HOME/settings.json" \
    "$(go_worker_settings_patch)" \
    "worker settings" || die "Could not update $CLAUDE_GO_HOME/settings.json"

  log "Linking go-worker into ~/.local/bin"
  mkdir -p "$(dirname "$link")"
  if [[ -e "$link" && ! -L "$link" ]]; then
    die "Refusing to replace a file that is not a symlink: $link"
  fi
  ln -sfn "$REPO_DIR/bin/go-worker" "$link"

  if ! "$REPO_DIR/bin/go-key" >/dev/null 2>&1; then
    log "OpenCode Go key not found. Add OPENCODE_API_KEY to $AI_MEMORY_ENV_FILE before you use go/ roles."
  fi
}

install_skill() {
  local source="$1" name="$2"
  log "Installing/updating skill: $name"
  npx -y skills add "$source" -g -a claude-code -s "$name" -y --copy </dev/null || \
    die "Failed to install skill: $name"
}

install_required_skills() {
  local manifest_rows provider name source_ref _require_skill_file

  log "Installing/updating required skills"
  manifest_rows="$(python3 "$AGENT_STACK_HELPER" manifest "$SKILLS_MANIFEST")" || \
    die "Could not read the required skill manifest"
  while IFS=$'\t' read -r provider name source_ref _require_skill_file; do
    case "$provider" in
      upstream) install_skill "$source_ref" "$name" ;;
    esac
  done <<<"$manifest_rows"
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

# Every platform needs this block, not only macOS. The ai-memory CLI reads
# AI_MEMORY_SERVER_URL and AI_MEMORY_AUTH_TOKEN from the environment, never from
# the environment file, so every login shell must load its per-host ai-memory
# settings.
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
        '# A remote ai-memory service needs the client bearer. A local service',
        '# does not.',
        'if [[ "${AGENTS_AI_MEMORY_REMOTE_MODE:-false}" == "true" ]]; then',
        '  if [[ -z "${AI_MEMORY_AUTH_TOKEN:-}" && -f "$HOME/.config/ai-memory/client-token" ]]; then',
        '    AI_MEMORY_AUTH_TOKEN="$(tr -d \' \\r\\n\' < "$HOME/.config/ai-memory/client-token")"',
        '    export AI_MEMORY_AUTH_TOKEN',
        '  fi',
        'else',
        '  unset AI_MEMORY_AUTH_TOKEN',
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
