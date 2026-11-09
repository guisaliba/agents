# >>> guisaliba/agents Claude Code ai-memory wrapper >>>
# Keep these functions local to the interactive Bash process. They are not
# exported, so ai-memory and claude-worker resolve the native claude executable
# without recursing into this wrapper.
unalias claude claude-raw 2>/dev/null || true
unset -f claude claude-raw 2>/dev/null || true
export PATH="$HOME/.local/bin:$PATH"
# One behavior only: a local, always-managed ai-memory workstream in the current
# directory. `claude --new` first creates a fresh Git worktree, so two sessions
# in one repository never share a working tree.
claude() {
  # A CLI subcommand or a version/help request is not a session, so it runs the
  # native claude without a managed workstream. test.sh checks this list
  # against `claude --help`.
  case "${1:-}" in
    # native subcommands: agents attach auth auto-mode doctor gateway import install kill logs mcp plugin plugins purge respawn rm setup-token stop ultrareview update upgrade
    agents|attach|auth|auto-mode|doctor|gateway|import|install|kill|logs|mcp|plugin|plugins|purge|respawn|rm|setup-token|stop|ultrareview|update|upgrade|-h|--help|-v|--version)
      command claude "$@"
      return
      ;;
  esac

  local argument new_worktree=false previous=""
  local forwarded=()
  for argument in "$@"; do
    if [[ "$argument" == "--dangerously-skip-permissions" ||
      "$argument" == "--permission-mode=bypassPermissions" ||
      ( "$previous" == "--permission-mode" && "$argument" == "bypassPermissions" ) ]]; then
      printf '%s\n' \
        'Refusing an unsandboxed bypass-permissions start. Run claude-raw only inside a sandbox you trust.' \
        >&2
      return 2
    fi
    previous="$argument"
    if [[ "$argument" == "--new" ]]; then
      new_worktree=true
      continue
    fi
    forwarded+=("$argument")
  done

  if [[ "$new_worktree" == true ]]; then
    local common_dir repository_root worktree_root slug worktree_dir
    if ! common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"; then
      printf '%s\n' \
        'claude --new needs a Git repository. Start a session without --new to use this directory.' \
        >&2
      return 2
    fi
    repository_root="$(dirname "$common_dir")"
    slug="$(date -u +%Y%m%d-%H%M%S)-$$"
    worktree_root="$repository_root-worktrees"
    worktree_dir="$worktree_root/$slug"
    if ! mkdir -p "$worktree_root" ||
      ! git worktree add -b "claude/$slug" "$worktree_dir" HEAD >&2; then
      printf '%s\n' 'claude --new could not create the worktree. No session was started.' >&2
      return 1
    fi
    printf 'worktree: %s\n' "$worktree_dir"
    printf 'branch:   claude/%s\n' "$slug"
    (
      cd "$worktree_dir" || exit 1
      command ai-memory run claude "${forwarded[@]}"
    )
    return
  fi

  command ai-memory run claude "${forwarded[@]}"
}
claude-raw() {
  command claude "$@"
}
# <<< guisaliba/agents Claude Code ai-memory wrapper <<<
