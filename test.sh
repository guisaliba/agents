#!/usr/bin/env bash
set -Eeuo pipefail

# test.sh
#
# Verifies the Claude Code + pstack agent stack.
#   ./test.sh --repo-only   deterministic fixtures; temporary HOME; no network
#   ./test.sh               the fixtures, then checks of this machine's install

repo_only=false
if [[ $# -gt 0 ]]; then
  if [[ $# -eq 1 && "$1" == "--repo-only" ]]; then
    repo_only=true
  else
    printf 'Usage: %s [--repo-only]\n' "$0" >&2
    exit 2
  fi
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$SCRIPT_DIR"
HELPER="$REPO_DIR/lib/agent_stack.py"
REAL_HOME="$HOME"
failures=0
passes=0

pass() { passes=$((passes + 1)); printf 'ok    %s\n' "$*"; }
fail() { failures=$((failures + 1)); printf 'FAIL  %s\n' "$*"; }
expect() {
  local label="$1"; shift
  if "$@"; then pass "$label"; else fail "$label"; fi
}
file_contains() { grep -qF -- "$2" "$1"; }
file_lacks() { ! grep -qF -- "$2" "$1"; }

FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT

# --- Static checks ---------------------------------------------------------

static_checks() {
  printf '\n== Static checks\n'
  expect "Bash syntax" bash -n "$REPO_DIR/apply.sh" "$REPO_DIR/test.sh" \
    "$REPO_DIR"/lib/*.bash "$REPO_DIR/bin/go-worker" "$REPO_DIR/bin/go-key" \
    "$REPO_DIR/shell/claude.bash"
  expect "Python helper compiles" python3 -B -m py_compile "$HELPER"
  if command -v shellcheck >/dev/null 2>&1; then
    expect "shellcheck on new entry points" shellcheck -x -S warning \
      "$REPO_DIR/bin/go-worker" "$REPO_DIR/bin/go-key" "$REPO_DIR/lib/claude.bash" \
      "$REPO_DIR/shell/claude.bash"
  else
    printf 'skip  shellcheck not installed\n'
  fi
  expect "go-worker and go-key are executable" test -x "$REPO_DIR/bin/go-worker" -a -x "$REPO_DIR/bin/go-key"

  expect "roster rows have four fields and unique aliases" python3 -B - "$REPO_DIR/claude/go-models.tsv" <<'PY'
import sys
seen = set()
for line in open(sys.argv[1], encoding="utf-8"):
    line = line.rstrip("\n")
    if not line.strip() or line.startswith("#"):
        continue
    fields = line.split("\t")
    if len(fields) != 4 or fields[0] in seen or not fields[3].isdigit():
        raise SystemExit(1)
    seen.add(fields[0])
raise SystemExit(0 if seen else 1)
PY

  expect "every go/ role in pstack-models.md exists in the roster" python3 -B - \
    "$REPO_DIR/claude/rules/pstack-models.md" "$REPO_DIR/claude/go-models.tsv" <<'PY'
import re
import sys
roster = {l.split("\t")[0] for l in open(sys.argv[2], encoding="utf-8")
          if l.strip() and not l.startswith("#")}
used = set(re.findall(r"go/([A-Za-z0-9.\-]+)", open(sys.argv[1], encoding="utf-8").read()))
missing = used - roster
if missing:
    print("missing:", sorted(missing))
raise SystemExit(0 if used and not missing else 1)
PY

  expect "pstack-models.md defines every pstack role" python3 -B - "$REPO_DIR/claude/rules/pstack-models.md" <<'PY'
import sys
roles = {"feature, refactoring", "bug-fix", "perf-issue", "hillclimb", "judgment and prose",
         "hardest tasks", "how explorer", "how explainer", "why investigators", "why synthesizer",
         "reflect tooling", "reflect judgment, divergent, synthesizer", "arena runners",
         "arena cross-judge pool", "swarm workers", "architect runners", "interrogate reviewers"}
found = {line.split(":", 1)[0] for line in open(sys.argv[1], encoding="utf-8")
         if line.strip() and not line.startswith("#") and ":" in line}
raise SystemExit(0 if roles <= found else 1)
PY

  expect "no retired OpenCode payload remains" bash -c \
    '! test -e "$0/opencode" -o -e "$0/plugins" -o -e "$0/mcps" -o -e "$0/shell/opencode.bash" -o -e "$0/skills.tsv"' "$REPO_DIR"
}

# --- Helper fixtures -------------------------------------------------------

helper_fixtures() {
  printf '\n== Helper fixtures\n'
  local dir="$FIXTURE_ROOT/helper" before after
  mkdir -p "$dir"
  local start="# >>> guisaliba/agents Claude Code ai-memory wrapper >>>"
  local end="# <<< guisaliba/agents Claude Code ai-memory wrapper <<<"
  local old_start="# >>> dotfiles OpenCode ai-memory wrapper >>>"
  local old_end="# <<< dotfiles OpenCode ai-memory wrapper <<<"

  printf '%s\n' 'alias ll="ls -l"' "$old_start" 'opencode() { :; }' "$old_end" 'export KEEP=1' >"$dir/aliases"
  python3 -B "$HELPER" merge-block "$REPO_DIR/shell/claude.bash" "$dir/aliases" "$start" "$end"
  python3 -B "$HELPER" remove-block "$dir/aliases" "$old_start" "$old_end"
  expect "remove-block leaves no doubled blank line" bash -c '! grep -Pzq "\n\n\n" "$0"' "$dir/aliases"
  expect "merge-block keeps unrelated lines" file_contains "$dir/aliases" 'export KEEP=1'
  expect "merge-block adds the Claude block" file_contains "$dir/aliases" "$start"
  expect "remove-block removes the retired OpenCode block" file_lacks "$dir/aliases" 'opencode() { :; }'
  before="$(sha256sum "$dir/aliases")"
  python3 -B "$HELPER" merge-block "$REPO_DIR/shell/claude.bash" "$dir/aliases" "$start" "$end"
  python3 -B "$HELPER" remove-block "$dir/aliases" "$old_start" "$old_end"
  after="$(sha256sum "$dir/aliases")"
  expect "block merge is idempotent" test "$before" == "$after"

  printf '%s\n' "$start" 'x' >"$dir/unbalanced"
  expect "merge-block refuses an unbalanced target" bash -c \
    '! python3 -B "$0" merge-block "$1" "$2" "$3" "$4" 2>/dev/null' \
    "$HELPER" "$REPO_DIR/shell/claude.bash" "$dir/unbalanced" "$start" "$end"

  printf '%s\n' '{"hooks": {"PreToolUse": [{"matcher": "Bash"}]}, "env": {"KEEP": "1"}, "permissions": {"allow": ["Bash(npm test)"]}}' >"$dir/settings.json"
  local patch='{"model": "opus", "env": {"NEW": "2"}, "permissions": {"allow": ["Bash(go-worker run *)"]}}'
  python3 -B "$HELPER" merge-json "$dir/settings.json" "$patch" settings
  expect "merge-json keeps foreign hooks, env keys, and allow rules" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["hooks"]["PreToolUse"][0]["matcher"] == "Bash"
assert d["env"] == {"KEEP": "1", "NEW": "2"} and d["model"] == "opus"
assert d["permissions"]["allow"] == ["Bash(npm test)", "Bash(go-worker run *)"]' "$dir/settings.json"
  before="$(sha256sum "$dir/settings.json")"
  python3 -B "$HELPER" merge-json "$dir/settings.json" "$patch" settings
  after="$(sha256sum "$dir/settings.json")"
  expect "merge-json is idempotent" test "$before" == "$after"
  printf 'not json' >"$dir/bad.json"
  expect "merge-json refuses invalid JSON" bash -c \
    '! python3 -B "$0" merge-json "$1" "{}" settings 2>/dev/null' "$HELPER" "$dir/bad.json"
}

# --- go-key and go-worker fixtures ----------------------------------------

make_fake_claude() {
  local path="$1" log_dir="$2" mode_file="$3"
  {
    printf '%s\n' '#!/usr/bin/env bash' \
      '# Fake claude for go-worker fixtures. Records argv, environment, and stdin.' \
      "log_dir='$log_dir'" "mode_file='$mode_file'"
    cat <<'FAKE'
printf '%s\n' "$@" >"$log_dir/argv"
env | sort >"$log_dir/env"
cat >"$log_dir/stdin"
printf '%s\n' "$PWD" >"$log_dir/cwd"
case "$(cat "$mode_file" 2>/dev/null || echo ok)" in
  ok) printf '%s\n' '{"type":"result","is_error":false,"result":"**Result**: done.","num_turns":3,"session_id":"s1","usage":{"input_tokens":120,"output_tokens":40,"cache_read_input_tokens":800,"cache_creation_input_tokens":10}}' ;;
  error) printf '%s\n' '{"type":"result","is_error":true,"result":"model not found","num_turns":1,"usage":{}}' ;;
  crash) printf 'boom\n' >&2; exit 7 ;;
esac
FAKE
  } >"$path"
  chmod +x "$path"
}

worker_fixtures() {
  printf '\n== go-key and go-worker fixtures\n'
  local dir="$FIXTURE_ROOT/worker"
  local home="$dir/home" profile="$dir/home/.claude-go" logs="$dir/logs" work="$dir/work"
  local secret="sk-fixture-$$-do-not-leak"
  mkdir -p "$home/.config/ai-memory" "$profile" "$logs" "$work"
  printf 'OTHER=1\nOPENCODE_API_KEY=%s\n' "$secret" >"$home/.config/ai-memory/env"
  printf '%s\n' "{\"apiKeyHelper\": \"$REPO_DIR/bin/go-key\", \"env\": {\"ANTHROPIC_BASE_URL\": \"https://opencode.ai/inference/go/anthropic\"}}" >"$profile/settings.json"
  make_fake_claude "$dir/claude" "$logs" "$dir/mode"
  printf 'Do the fixture task.\n' >"$work/brief.md"

  run_worker() {
    env HOME="$home" CLAUDE_GO_CONFIG_DIR="${PROFILE_OVERRIDE:-$profile}" XDG_STATE_HOME="$home/.local/state" \
      GO_WORKER_CLAUDE_BIN="$dir/claude" \
      CLAUDECODE=1 ANTHROPIC_API_KEY=sk-coordinator ANTHROPIC_MODEL=opus \
      "$REPO_DIR/bin/go-worker" "$@"
  }

  expect "go-key prints the configured key" bash -c \
    '[[ "$(HOME="$0" "$1/bin/go-key")" == "$2" ]]' "$home" "$REPO_DIR" "$secret"
  expect "go-key fails without a key" bash -c \
    '! HOME="$0" AGENTS_GO_KEY_ENV_FILE=/nonexistent "$1/bin/go-key" 2>/dev/null' "$home" "$REPO_DIR"

  local status=0
  run_worker run --model go/kimi-k3.1 --dir "$work" --brief "$work/brief.md" --report "$work/report.md" >/dev/null 2>&1 || status=$?
  expect "write run exits 0" test "$status" -eq 0
  expect "write run resolves the alias to the Go model id" file_contains "$logs/argv" 'kimi-k3.1-pro'
  expect "write run uses acceptEdits" file_contains "$logs/argv" 'acceptEdits'
  expect "write run disables prompts and the Agent tool" bash -c \
    'grep -qx none "$0" && grep -qx "Agent,WebSearch" "$0"' "$logs/argv"
  expect "worker receives the brief on stdin" file_contains "$logs/stdin" 'Do the fixture task.'
  expect "worker runs in --dir" bash -c '[[ "$(cat "$0")" == "$1" ]]' "$logs/cwd" "$work"
  expect "worker gets CLAUDE_CONFIG_DIR of the Go profile" file_contains "$logs/env" "CLAUDE_CONFIG_DIR=$profile"
  expect "worker environment drops coordinator variables" bash -c \
    '! grep -qE "^(CLAUDECODE|ANTHROPIC_API_KEY|ANTHROPIC_MODEL)=" "$0"' "$logs/env"
  expect "the key never reaches argv or the worker environment" bash -c \
    '! grep -qF "$0" "$1" "$2"' "$secret" "$logs/argv" "$logs/env"
  expect "report holds the worker result" file_contains "$work/report.md" '**Result**: done.'
  expect "meta records success and usage" python3 -B -c '
import json, sys
m = json.load(open(sys.argv[1]))
assert m["succeeded"] and m["model_id"] == "kimi-k3.1-pro" and m["family"] == "kimi"
assert m["usage"]["output_tokens"] == 40 and m["mode"] == "write"' "$work/report.md.meta.json"
  expect "ledger records the run" file_contains "$home/.local/state/go-worker/runs.tsv" $'go/kimi-k3.1\tkimi-k3.1-pro\twrite\tyes'

  run_worker run --model deepseek-v4.1-flash --dir "$work" --brief "$work/brief.md" --report "$work/judge.md" --readonly >/dev/null 2>&1 || true
  expect "readonly run uses dontAsk with read-only tools" bash -c \
    'grep -qx dontAsk "$0" && grep -q "^Read,Glob,Grep" "$0" && ! grep -qx acceptEdits "$0"' "$logs/argv"

  status=0
  echo error >"$dir/mode"; run_worker run --model go/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/err.md" >/dev/null 2>&1 || status=$?
  expect "an is_error result exits 1" test "$status" -eq 1
  status=0
  echo crash >"$dir/mode"; run_worker run --model go/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/crash.md" >/dev/null 2>&1 || status=$?
  expect "a crashed worker exits 1 and writes a placeholder report" bash -c \
    '[[ "$0" == 1 ]] && grep -q "worker produced no report" "$1"' "$status" "$work/crash.md"
  status=0
  run_worker run --model go/nope --dir "$work" --brief "$work/brief.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "an unknown alias exits 2" test "$status" -eq 2
  status=0
  run_worker run --model go/glm-5.3 --dir "$work" --brief "$work/missing.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "a missing brief exits 2" test "$status" -eq 2
  status=0
  echo ok >"$dir/mode"
  PROFILE_OVERRIDE="$dir/absent" run_worker run --model go/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "a missing worker profile exits 3" test "$status" -eq 3
  status=0
  AGENTS_GO_KEY_ENV_FILE=/nonexistent run_worker run --model go/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "a missing OpenCode Go key exits 3" test "$status" -eq 3

  expect "usage aggregates the ledger" bash -c \
    'env HOME="$0" XDG_STATE_HOME="$0/.local/state" "$1/bin/go-worker" usage | grep -q "^go/glm-5.3"' "$home" "$REPO_DIR"
  expect "models lists the roster with the go/ prefix" bash -c \
    '"$0/bin/go-worker" models | grep -q "^go/kimi-k3.1	kimi-k3.1-pro	kimi"' "$REPO_DIR"
}

# --- apply.sh fixtures (offline functions only) ---------------------------

apply_fixtures() {
  printf '\n== apply.sh fixtures (offline functions)\n'
  local home="$FIXTURE_ROOT/apply-home" first second
  mkdir -p "$home"
  printf '%s\n' '# >>> dotfiles OpenCode ai-memory wrapper >>>' 'opencode() { :; }' '# <<< dotfiles OpenCode ai-memory wrapper <<<' >"$home/.bash_aliases"

  run_offline_apply() {
    env -i HOME="$home" PATH="$PATH" bash -c '
      set -Eeuo pipefail
      source "$0/apply.sh"
      configure_claude_main_profile
      configure_go_worker_profile
      merge_claude_shell_block
      configure_bash_login_env
    ' "$REPO_DIR" >/dev/null
  }
  snapshot() {
    (cd "$home" && find . -type f -o -type l | sort | while read -r f; do
      if [[ -L "$f" ]]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else sha256sum "$f"; fi
    done)
  }

  expect "offline apply functions succeed" run_offline_apply
  expect "~/.claude/CLAUDE.md is a copy of the repository CLAUDE.md" cmp -s "$REPO_DIR/CLAUDE.md" "$home/.claude/CLAUDE.md"
  expect "managed rules are installed" bash -c \
    'for r in pstack-models.md pstack-go.md; do cmp -s "$0/claude/rules/$r" "$1/.claude/rules/$r" || exit 1; done' \
    "$REPO_DIR" "$home"
  expect "main settings select Opus and allow go-worker runs" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["model"] == "opus" and "Bash(go-worker run *)" in d["permissions"]["allow"]' "$home/.claude/settings.json"
  expect "worker settings point at OpenCode Go through go-key" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["apiKeyHelper"] == sys.argv[2]
assert d["env"]["ANTHROPIC_BASE_URL"] == "https://opencode.ai/inference/go/anthropic"
assert d["env"]["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] == "1"' "$home/.claude-go/settings.json" "$REPO_DIR/bin/go-key"
  expect "main settings carry no OpenCode Go routing" file_lacks "$home/.claude/settings.json" 'opencode.ai'
  expect "worker CLAUDE.md is installed" cmp -s "$REPO_DIR/claude/worker/CLAUDE.md" "$home/.claude-go/CLAUDE.md"
  expect "go-worker is linked into ~/.local/bin" bash -c '[[ "$(readlink "$0")" == "$1" ]]' \
    "$home/.local/bin/go-worker" "$REPO_DIR/bin/go-worker"
  expect "bash aliases gain the Claude block and lose the OpenCode block" bash -c \
    'grep -qF "Claude Code ai-memory wrapper >>>" "$0" && ! grep -qF "opencode() { :; }" "$0"' "$home/.bash_aliases"
  expect "login profile loads aliases and the ai-memory environment" bash -c \
    'grep -qF "source \"\$HOME/.bash_aliases\"" "$0" && grep -qF ".config/ai-memory/env" "$0" && ! grep -q opencode "$0"' \
    "$home/.bash_profile"

  first="$(snapshot)"
  run_offline_apply
  second="$(snapshot)"
  expect "offline apply functions are idempotent" test "$first" == "$second"
  [[ "$first" == "$second" ]] || diff <(printf "%s\n" "$first") <(printf "%s\n" "$second") || true
}

# --- Bash wrapper fixtures -------------------------------------------------

wrapper_fixtures() {
  printf '\n== Bash wrapper fixtures\n'
  local dir="$FIXTURE_ROOT/wrapper"
  mkdir -p "$dir/bin"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" >"$WRAPPER_LOG"' >"$dir/bin/ai-memory"
  chmod +x "$dir/bin/ai-memory"

  wrapper() {
    env -i HOME="$dir" PATH="$dir/bin:/usr/bin:/bin" WRAPPER_LOG="$dir/log" bash -c \
      'source "$0"; claude "$@"' "$REPO_DIR/shell/claude.bash" "$@"
  }

  wrapper --continue >/dev/null 2>&1
  expect "claude starts an ai-memory managed workstream" bash -c \
    '[[ "$(tr "\n" " " <"$0")" == "run claude --continue " ]]' "$dir/log"
  expect "claude refuses --dangerously-skip-permissions" bash -c \
    '! "$@" >/dev/null 2>&1' _ env -i HOME="$dir" PATH="$dir/bin:/usr/bin:/bin" WRAPPER_LOG="$dir/log" bash -c \
    'source "$0"; claude --dangerously-skip-permissions' "$REPO_DIR/shell/claude.bash"
  expect "claude refuses --permission-mode bypassPermissions" bash -c \
    '! "$@" >/dev/null 2>&1' _ env -i HOME="$dir" PATH="$dir/bin:/usr/bin:/bin" WRAPPER_LOG="$dir/log" bash -c \
    'source "$0"; claude --permission-mode bypassPermissions' "$REPO_DIR/shell/claude.bash"
  expect "the wrapper functions are not exported to child processes" bash -c \
    'source "$0"; ! bash -c "declare -F claude >/dev/null 2>&1"' "$REPO_DIR/shell/claude.bash"
}

# --- Machine checks ---------------------------------------------------------

machine_checks() {
  printf '\n== Machine checks (this host)\n'
  local home="$REAL_HOME"
  PATH="$home/.local/bin:$PATH"

  expect "claude is installed" bash -c 'type -P claude >/dev/null'
  expect "pstack plugin is installed" bash -c 'claude plugin list 2>/dev/null | grep -q "pstack@cursor-plugins"'
  expect "~/.claude/CLAUDE.md starts with the repository CLAUDE.md" bash -c \
    'head -c "$(wc -c <"$0")" "$1" | cmp -s - "$0"' "$REPO_DIR/CLAUDE.md" "$home/.claude/CLAUDE.md"
  expect "managed rules are current" bash -c \
    'for r in pstack-models.md pstack-go.md; do cmp -s "$0/claude/rules/$r" "$1/.claude/rules/$r" || exit 1; done' \
    "$REPO_DIR" "$home"
  expect "ai-memory routing rule exists" test -s "$home/.claude/rules/ai-memory.md"
  expect "ai-memory hooks are in the main profile" file_contains "$home/.claude/settings.json" 'ai-memory'
  expect "RTK hook is in the main profile" file_contains "$home/.claude/settings.json" 'rtk'
  expect "RTK hook is in the worker profile" file_contains "$home/.claude-go/settings.json" 'rtk'
  expect "ai-memory hooks stay out of the worker profile" file_lacks "$home/.claude-go/settings.json" 'ai-memory'
  expect "go-worker is on PATH" bash -c 'command -v go-worker >/dev/null'
  expect "ai-memory service answers" bash -c 'ai-memory status --json >/dev/null 2>&1'
  expect "bash aliases carry the Claude block" file_contains "$home/.bash_aliases" 'Claude Code ai-memory wrapper >>>'
  printf '\nRun `go-worker doctor` (and `go-worker doctor --live`) to check the OpenCode Go side.\n'
}

static_checks
helper_fixtures
worker_fixtures
apply_fixtures
wrapper_fixtures
if [[ "$repo_only" == false ]]; then
  machine_checks
fi

printf '\n%s passed, %s failed\n' "$passes" "$failures"
[[ "$failures" -eq 0 ]]
