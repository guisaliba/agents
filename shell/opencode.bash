# >>> dotfiles OpenCode ai-memory wrapper >>>
# Keep this function local to the interactive Bash process. ai-memory then
# resolves the native OpenCode executable without recursing into this wrapper.
unalias opencode opencode-local opencode-raw 2>/dev/null || true
unset -f opencode opencode-local opencode-raw 2>/dev/null || true
export PATH="$HOME/.opencode/bin:$PATH"
_opencode_remote_path() {
  local path="$1"
  local client_home="${OPENCODE_CLIENT_HOME:-$HOME}"
  local server_home="${OPENCODE_SERVER_HOME:-$HOME}"
  case "$path" in
    "$client_home") printf '%s\n' "$server_home" ;;
    "$client_home"/*) printf '%s%s\n' "$server_home" "${path#$client_home}" ;;
    *) printf '%s\n' "$path" ;;
  esac
}
opencode() {
  local argument mapped_path
  local remote_arguments=()
  for argument in "$@"; do
    if [[ "$argument" == "--yolo" || "$argument" == "--auto" ]]; then
      printf '%s\n' \
        'Refusing an unjailed OpenCode dangerous-mode start. Use the documented ai-jail ai-memory run opencode --yolo command.' \
        >&2
      return 2
    fi
  done
  if [[ -f "$HOME/.config/opencode/server.env" ]]; then
    set -a
    source "$HOME/.config/opencode/server.env"
    set +a
  fi
  if [[ -n "${OPENCODE_SERVER_URL:-}" ]]; then
    if [[ $# -eq 0 ]]; then
      remote_arguments+=("$(_opencode_remote_path "$PWD")")
    else
      for argument in "$@"; do
        mapped_path="$(_opencode_remote_path "$argument")"
        remote_arguments+=("$mapped_path")
      done
    fi
    "$HOME/.opencode/bin/opencode" --server "$OPENCODE_SERVER_URL" "${remote_arguments[@]}"
    return
  fi
  command ai-memory run "$HOME/.opencode/bin/opencode" "$@"
}
opencode-local() {
  command ai-memory run "$HOME/.opencode/bin/opencode" "$@"
}
opencode-raw() {
  "$HOME/.opencode/bin/opencode" "$@"
}
# <<< dotfiles OpenCode ai-memory wrapper <<<
