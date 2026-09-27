# >>> dotfiles OpenCode ai-memory wrapper >>>
# Keep this function local to the interactive Bash process. ai-memory then
# resolves the native OpenCode executable without recursing into this wrapper.
unalias opencode opencode-raw 2>/dev/null || true
unset -f opencode opencode-raw 2>/dev/null || true
export PATH="$HOME/.opencode/bin:$PATH"
# One behavior only: a local, always-managed ai-memory workstream. The session
# runs in the current directory on the machine you typed the command on, so a
# session started on a client workstation is a client session. To work on the
# M4, run this command on the M4. The OpenCode server and its web UI remain
# available for a browser or phone, but the shell never drives it with --server,
# so no client path is ever translated into a server path.
opencode() {
  local argument new_worktree=false
  local forwarded=()
  for argument in "$@"; do
    if [[ "$argument" == "--yolo" || "$argument" == "--auto" ]]; then
      printf '%s\n' \
        'Refusing an unjailed OpenCode dangerous-mode start. Use the documented ai-jail ai-memory run opencode --yolo command.' \
        >&2
      return 2
    fi
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
        'opencode --new needs a Git repository. Start a session without --new to use this directory.' \
        >&2
      return 2
    fi
    repository_root="$(dirname "$common_dir")"
    slug="$(date -u +%Y%m%d-%H%M%S)-$$"
    worktree_root="$repository_root-worktrees"
    worktree_dir="$worktree_root/$slug"
    if ! mkdir -p "$worktree_root" ||
      ! git worktree add -b "opencode/$slug" "$worktree_dir" HEAD >&2; then
      printf '%s\n' 'opencode --new could not create the worktree. No session was started.' >&2
      return 1
    fi
    printf 'worktree: %s\n' "$worktree_dir"
    printf 'branch:   opencode/%s\n' "$slug"
    (
      cd "$worktree_dir" || exit 1
      command ai-memory run opencode2 --executable "$HOME/.opencode/bin/opencode" "${forwarded[@]}"
    )
    return
  fi

  command ai-memory run opencode2 --executable "$HOME/.opencode/bin/opencode" "${forwarded[@]}"
}
opencode-raw() {
  "$HOME/.opencode/bin/opencode" "$@"
}
# <<< dotfiles OpenCode ai-memory wrapper <<<
