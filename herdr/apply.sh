#!/usr/bin/env bash
set -Eeuo pipefail

HERDR_APPLY_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
HERDR_APPLY_REPO_DIR="$(cd -- "$HERDR_APPLY_DIR/.." && pwd)"

source "$HERDR_APPLY_REPO_DIR/apply.sh"

focused_herdr_main() {
  if [[ $# -ne 0 ]]; then
    printf 'Usage: %s\n' "$0" >&2
    return 2
  fi

  log "Starting focused Herdr setup"

  setup_herdr
  merge_opencode_shell_override
  copy_agents_md
  install_manifest_skill herdr

  log "Focused Herdr setup complete. Open a new Bash shell or source ~/.bash_aliases."
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  focused_herdr_main "$@"
fi
