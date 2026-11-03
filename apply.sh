#!/usr/bin/env bash
set -Eeuo pipefail

# apply.sh
#
# Deterministic Claude Code + pstack setup script.
# Installs Claude Code, the pstack plugin, the worker profile used by pstack
# worker/ roles, RTK, and ai-memory.
# Re-running converges the same state.
#
# Usage:
#   ./apply.sh
#
# Prerequisites: bash, curl, git, python3 3.11+, and systemctl on Linux. AUR package installation also needs yay when ai-memory is absent.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
AGENT_STACK_HELPER="$REPO_DIR/lib/agent_stack.py"

# The main profile is always ~/.claude. A CLAUDE_CONFIG_DIR exported by the
# caller would redirect Claude Code, RTK, and ai-memory installers elsewhere.
unset CLAUDE_CONFIG_DIR

CLAUDE_INSTALL_URL="https://claude.ai/install.sh"
# The built-in you-should-know mod requires 2.1.287. claude-worker needs only
# 2.1.259 (--permission-prompts), so the mod sets the floor.
CLAUDE_MIN_VERSION="${CLAUDE_MIN_VERSION:-2.1.287}"
CLAUDE_HOME="$HOME/.claude"
CLAUDE_RULES_DIR="$CLAUDE_HOME/rules"
CLAUDE_MAIN_MODEL="opus"
# Built-in Claude Code mod: https://code.claude.com/docs/en/interactive-mode#you-should-know-suggestions
CLAUDE_YOU_SHOULD_KNOW_PLUGIN="cc-plugin-you-should-know@builtin"
CLAUDE_MANAGED_RULES=(pstack-models.md pstack-workers.md)
CLAUDE_WORKER_HOME="${CLAUDE_WORKER_CONFIG_DIR:-$HOME/.claude-worker}"
WORKER_PROVIDER_FILE="$REPO_DIR/claude/worker/provider.env"
PSTACK_MARKETPLACE_SOURCE="cursor/plugins"
PSTACK_MARKETPLACE_NAME="cursor-plugins"
PSTACK_PLUGIN="pstack@cursor-plugins"
RTK_VERSION="${RTK_VERSION:-v1.1.0}"
AI_MEMORY_AUR_PACKAGE="${AI_MEMORY_AUR_PACKAGE:-ai-memory-bin}"
AI_MEMORY_MIN_VERSION="${AI_MEMORY_MIN_VERSION:-3.3.1}"
AI_MEMORY_RELEASE_VERSION="${AI_MEMORY_RELEASE_VERSION:-3.3.1}"
AI_MEMORY_RELEASE_BASE_URL="https://github.com/akitaonrails/ai-memory/releases/download/v$AI_MEMORY_RELEASE_VERSION"
AI_MEMORY_MACOS_AARCH64_SHA256="0289d5b6ed3d371216bf086addc65e5f1beedff76cf6e640ad9fe4ddba70a18a"
AI_MEMORY_MACOS_X86_64_SHA256="991d6b1053bfe742f1a4e2de46627522b8a5bb4d4b48f50dfad73b122464e1ae"
AI_MEMORY_INSTALL_ROOT="${AI_MEMORY_INSTALL_ROOT:-$HOME/.local/opt/ai-memory/$AI_MEMORY_RELEASE_VERSION}"
AI_MEMORY_BINARY="${AI_MEMORY_BINARY:-$HOME/.local/bin/ai-memory}"
AI_MEMORY_DATA_DIR="$HOME/.local/share/ai-memory"
AI_MEMORY_CONFIG_FILE="$HOME/.config/ai-memory/config.toml"
AI_MEMORY_ENV_FILE="$HOME/.config/ai-memory/env"
# Every host runs its own loopback service. The ai-memory CLI uses the same
# URL by default.
AI_MEMORY_SERVER_URL="http://127.0.0.1:49374"
AI_MEMORY_INSTRUCTIONS_FILE="$CLAUDE_RULES_DIR/ai-memory.md"
AI_MEMORY_USER_SERVICE_FILE="$HOME/.config/systemd/user/ai-memory.service"
AI_MEMORY_LAUNCH_AGENT_LABEL="com.github.akitaonrails.ai-memory"
AI_MEMORY_LAUNCH_AGENT_FILE="$HOME/Library/LaunchAgents/$AI_MEMORY_LAUNCH_AGENT_LABEL.plist"
AI_MEMORY_LAUNCH_DAEMON_LABEL="com.github.akitaonrails.ai-memory"
AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE="${AI_MEMORY_LAUNCH_DAEMON_SOURCE_FILE:-$HOME/.config/ai-memory/$AI_MEMORY_LAUNCH_DAEMON_LABEL.plist}"
AI_MEMORY_LAUNCH_DAEMON_FILE="${AI_MEMORY_LAUNCH_DAEMON_FILE:-/Library/LaunchDaemons/$AI_MEMORY_LAUNCH_DAEMON_LABEL.plist}"
AI_MEMORY_LAUNCH_DAEMON_LOG_DIR="$HOME/Library/Logs/ai-memory"
BASH_ALIASES_SOURCE="${BASH_ALIASES_SOURCE:-$REPO_DIR/shell/claude.bash}"
BASH_ALIASES_FILE="$HOME/.bash_aliases"
CLAUDE_SHELL_BLOCK_START="# >>> guisaliba/agents Claude Code ai-memory wrapper >>>"
CLAUDE_SHELL_BLOCK_END="# <<< guisaliba/agents Claude Code ai-memory wrapper <<<"
RETIRED_OPENCODE_SHELL_BLOCK_START="# >>> dotfiles OpenCode ai-memory wrapper >>>"
RETIRED_OPENCODE_SHELL_BLOCK_END="# <<< dotfiles OpenCode ai-memory wrapper <<<"
BASH_PROFILE="$HOME/.bash_profile"
BASH_PROFILE_BLOCK_START="# >>> guisaliba/agents Bash aliases >>>"
BASH_PROFILE_BLOCK_END="# <<< guisaliba/agents Bash aliases <<<"

# shellcheck source=lib/common.bash
source "$REPO_DIR/lib/common.bash"
# shellcheck source=lib/ai-memory.bash
source "$REPO_DIR/lib/ai-memory.bash"
# shellcheck source=lib/rtk.bash
source "$REPO_DIR/lib/rtk.bash"
# shellcheck source=lib/claude.bash
source "$REPO_DIR/lib/claude.bash"

main() {
  log "Starting Claude Code + pstack agent stack setup"

  prepare_platform_prerequisites
  check_prerequisites
  prepend_path "$HOME/.local/bin"
  install_claude_code
  install_ai_memory
  verify_ai_memory_unauthenticated_loopback
  install_rtk

  configure_claude_main_profile
  setup_ai_memory
  warn_on_stale_ai_memory_service
  wire_rtk_to_claude_code "$CLAUDE_HOME"
  install_pstack_plugin

  configure_worker_profile
  wire_rtk_to_claude_code "$CLAUDE_WORKER_HOME"

  merge_claude_shell_block
  configure_bash_login_env

  log "Setup complete. Open a new Bash shell, run claude once to log in with the Claude Pro plan, then run ./test.sh and claude-worker doctor."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
