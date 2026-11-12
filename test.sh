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
# The installed instructions file is the source plus the RTK import line.
equals_source_with_rtk_import() { cmp -s <(cat "$1"; printf '\n@RTK.md\n') "$2"; }

FIXTURE_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$FIXTURE_ROOT"' EXIT

# --- Static checks ---------------------------------------------------------

static_checks() {
  printf '\n== Static checks\n'
  expect "Bash syntax" bash -n "$REPO_DIR/apply.sh" "$REPO_DIR/test.sh" \
    "$REPO_DIR"/lib/*.bash "$REPO_DIR/bin/claude-worker" "$REPO_DIR/bin/claude-worker-key" \
    "$REPO_DIR/shell/claude.bash"
  expect "Python helper compiles" python3 -B -m py_compile "$HELPER"
  if command -v shellcheck >/dev/null 2>&1; then
    expect "shellcheck on new entry points" shellcheck -x -S warning \
      "$REPO_DIR/bin/claude-worker" "$REPO_DIR/bin/claude-worker-key" "$REPO_DIR/lib/claude.bash" \
      "$REPO_DIR/shell/claude.bash"
  else
    printf 'skip  shellcheck not installed\n'
  fi
  expect "claude-worker and claude-worker-key are executable" test -x "$REPO_DIR/bin/claude-worker" -a -x "$REPO_DIR/bin/claude-worker-key"
  expect "provider.env defines every worker provider setting" bash -c \
    'for k in WORKER_PROVIDER WORKER_ANTHROPIC_BASE_URL WORKER_MODELS_URL WORKER_BACKGROUND_MODEL WORKER_SMOKE_ALIAS WORKER_API_KEY_ENV_FILE WORKER_API_KEY_VARIABLE; do python3 -B "$0" env-value "$1" "$k" >/dev/null || exit 1; done' \
    "$HELPER" "$REPO_DIR/claude/worker/provider.env"
  expect "the instruction sources do not import RTK.md (apply.sh adds the import to the installed copy)" bash -c \
    '! grep -qx "@RTK.md" "$0/CLAUDE.md" "$0/claude/worker/contract.md"' "$REPO_DIR"
  expect "no CLAUDE.md exists below the repository root (Claude Code loads nested CLAUDE.md files)" bash -c \
    '[[ -z "$(cd "$0" && git ls-files -- "*/CLAUDE.md")" ]]' "$REPO_DIR"
  expect "apply.sh requires Claude Code 2.1.287, the first release with the you-should-know mod" \
    grep -qx 'CLAUDE_MIN_VERSION="${CLAUDE_MIN_VERSION:-2.1.287}"' "$REPO_DIR/apply.sh"
  expect "the smoke alias exists in the roster" bash -c \
    'grep -q "^$(python3 -B "$0" env-value "$1" WORKER_SMOKE_ALIAS)	" "$2"' \
    "$HELPER" "$REPO_DIR/claude/worker/provider.env" "$REPO_DIR/claude/worker/models.tsv"

  expect "roster rows have four fields and unique aliases" python3 -B - "$REPO_DIR/claude/worker/models.tsv" <<'PY'
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

  expect "every worker/ role in pstack-models.md exists in the roster" python3 -B - \
    "$REPO_DIR/claude/rules/pstack-models.md" "$REPO_DIR/claude/worker/models.tsv" <<'PY'
import re
import sys
roster = {l.split("\t")[0] for l in open(sys.argv[2], encoding="utf-8")
          if l.strip() and not l.startswith("#")}
used = set(re.findall(r"worker/([A-Za-z0-9.\-]+)", open(sys.argv[1], encoding="utf-8").read()))
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
    '! test -e "$0/opencode" -o -e "$0/plugins" -o -e "$0/mcps" -o -e "$0/shell/opencode.bash" -o -e "$0/skills.tsv" -o -e "$0/AGENTS.md"' "$REPO_DIR"
  expect "no provider-specific names outside the provider files" bash -c \
    '! grep -rIn -E "go-worker|go-key|claude-go|(^|[^a-z-])go/[a-z]" "$0/apply.sh" "$0/lib" "$0/bin" "$0/shell" "$0/claude/rules" "$0/claude/worker/contract.md"' "$REPO_DIR"
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
  local patch='{"model": "opus", "env": {"NEW": "2"}, "permissions": {"allow": ["Bash(claude-worker run *)"]}}'
  python3 -B "$HELPER" merge-json "$dir/settings.json" "$patch" settings
  expect "merge-json keeps foreign hooks, env keys, and allow rules" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["hooks"]["PreToolUse"][0]["matcher"] == "Bash"
assert d["env"] == {"KEEP": "1", "NEW": "2"} and d["model"] == "opus"
assert d["permissions"]["allow"] == ["Bash(npm test)", "Bash(claude-worker run *)"]' "$dir/settings.json"
  before="$(sha256sum "$dir/settings.json")"
  python3 -B "$HELPER" merge-json "$dir/settings.json" "$patch" settings
  after="$(sha256sum "$dir/settings.json")"
  expect "merge-json is idempotent" test "$before" == "$after"
  printf 'not json' >"$dir/bad.json"
  expect "merge-json refuses invalid JSON" bash -c \
    '! python3 -B "$0" merge-json "$1" "{}" settings 2>/dev/null' "$HELPER" "$dir/bad.json"

  expect "run-with-deadline passes stdin and the exit status through" bash -c \
    '[[ "$(printf "in\n" | python3 -B "$0" run-with-deadline 10 bash -c "cat; exit 3"; echo "/$?")" == "in"$'"'"'\n'"'"'"/3" ]]' "$HELPER"
  expect "run-with-deadline exits 124 at the deadline" bash -c \
    'python3 -B "$0" run-with-deadline 1 sleep 30 2>/dev/null; [[ $? == 124 ]]' "$HELPER"
  python3 -B "$HELPER" run-with-deadline 60 bash -c \
    'trap "echo stopped >\"$0\"; exit 0" TERM; sleep 300 & wait' "$dir/forwarded" &
  local deadline_pid=$!
  sleep 1
  kill -TERM "$deadline_pid"
  wait "$deadline_pid" 2>/dev/null || true
  expect "run-with-deadline forwards SIGTERM to the command" grep -qx stopped "$dir/forwarded"
}

# --- claude-worker-key and claude-worker fixtures ---------------------------

make_fake_claude() {
  local path="$1" log_dir="$2" mode_file="$3"
  {
    printf '%s\n' '#!/usr/bin/env bash' \
      '# Fake claude for claude-worker fixtures. Records argv, environment, and stdin.' \
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
  sleep) sleep 20; printf '%s\n' '{"type":"result","is_error":false,"result":"late","num_turns":1,"usage":{}}' ;;
esac
FAKE
  } >"$path"
  chmod +x "$path"
}

# Print the current PATH with timeout removed. A directory that holds a
# timeout executable is replaced by a copy of its links without it, in a
# new directory under $1; every other directory stays as it is, so a long
# PATH (WSL2 adds the Windows directories) is not copied.
timeout_free_path() {
  local target="$1" entry command_path copy n=0 result=""
  local IFS=:
  for entry in $PATH; do
    [[ -n "$entry" ]] || continue
    if [[ -x "$entry/timeout" && ! -d "$entry/timeout" ]]; then
      n=$((n + 1))
      copy="$target/$n"
      mkdir -p "$copy"
      for command_path in "$entry"/*; do
        [[ "${command_path##*/}" == timeout ]] && continue
        ln -s "$command_path" "$copy/${command_path##*/}"
      done
      entry="$copy"
    fi
    result="${result:+$result:}$entry"
  done
  printf '%s\n' "$result"
}

worker_fixtures() {
  printf '\n== claude-worker-key and claude-worker fixtures\n'
  local dir="$FIXTURE_ROOT/worker"
  local home="$dir/home" profile="$dir/home/.claude-worker" logs="$dir/logs" work="$dir/work"
  local secret="sk-fixture-$$-do-not-leak"
  local repo="$dir/repo"
  mkdir -p "$home/.config/ai-memory" "$profile" "$logs" "$repo"
  # A write seat must run in its own linked worktree, so the fixture work
  # directory is one. The main working tree is the read-only checkout.
  git -C "$repo" init -q
  git -C "$repo" -c user.email=fixture@example.com -c user.name=fixture commit -q --allow-empty -m init
  git -C "$repo" worktree add -q --detach "$work"
  printf 'OTHER=1\nOPENCODE_API_KEY=%s\n' "$secret" >"$home/.config/ai-memory/env"
  printf '%s\n' "{\"apiKeyHelper\": \"$REPO_DIR/bin/claude-worker-key\", \"env\": {\"ANTHROPIC_BASE_URL\": \"https://opencode.ai/inference/go/anthropic\"}}" >"$profile/settings.json"
  make_fake_claude "$dir/claude" "$logs" "$dir/mode"
  printf 'Do the fixture task.\n' >"$work/brief.md"

  run_worker() {
    env HOME="$home" CLAUDE_WORKER_CONFIG_DIR="${PROFILE_OVERRIDE:-$profile}" XDG_STATE_HOME="$home/.local/state" \
      CLAUDE_WORKER_CLAUDE_BIN="$dir/claude" ${KEY_FILE_OVERRIDE:+CLAUDE_WORKER_KEY_ENV_FILE="$KEY_FILE_OVERRIDE"} \
      CLAUDECODE=1 ANTHROPIC_API_KEY=sk-coordinator ANTHROPIC_MODEL=opus \
      "$REPO_DIR/bin/claude-worker" "$@"
  }

  expect "claude-worker-key prints the key that provider.env names" bash -c \
    '[[ "$(HOME="$0" "$1/bin/claude-worker-key")" == "$2" ]]' "$home" "$REPO_DIR" "$secret"
  expect "claude-worker-key fails without a key file" bash -c \
    '! HOME="$0" CLAUDE_WORKER_KEY_ENV_FILE=/nonexistent "$1/bin/claude-worker-key" 2>/dev/null' "$home" "$REPO_DIR"

  local status=0
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief "$work/brief.md" --report "$work/report.md" >/dev/null 2>&1 || status=$?
  expect "write run exits 0" test "$status" -eq 0
  cp "$logs/argv" "$logs/argv.write"
  expect "write run resolves the alias to the Go model id" file_contains "$logs/argv" 'kimi-k3.1-pro'
  expect "write run uses acceptEdits" file_contains "$logs/argv" 'acceptEdits'
  expect "write run disables prompts and the Agent tool" bash -c \
    'grep -qx none "$0" && grep -qx "Agent,WebSearch" "$0"' "$logs/argv"
  expect "worker receives the brief on stdin" file_contains "$logs/stdin" 'Do the fixture task.'
  expect "worker runs in --dir" bash -c '[[ "$(cat "$0")" == "$1" ]]' "$logs/cwd" "$work"
  expect "worker gets CLAUDE_CONFIG_DIR of the worker profile" file_contains "$logs/env" "CLAUDE_CONFIG_DIR=$profile"
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
  expect "ledger records the run" file_contains "$home/.local/state/claude-worker/runs.tsv" $'worker/kimi-k3.1\tkimi-k3.1-pro\twrite\tyes'

  local lock
  lock="$(git -C "$work" rev-parse --absolute-git-dir)/claude-worker.lock"
  status=0
  run_worker run --model worker/kimi-k3.1 --dir "$repo" --brief "$work/brief.md" --report "$work/main.md" >/dev/null 2>&1 || status=$?
  expect "a write run in the main working tree exits 2" test "$status" -eq 2
  status=0
  mkdir -p "$dir/plain"
  run_worker run --model worker/kimi-k3.1 --dir "$dir/plain" --brief "$work/brief.md" --report "$work/plain.md" >/dev/null 2>&1 || status=$?
  expect "a write run outside a Git worktree exits 2" test "$status" -eq 2
  status=0
  mkdir "$lock" && printf '%s\n' "$$" >"$lock/pid"
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief "$work/brief.md" --report "$work/busy.md" >/dev/null 2>&1 || status=$?
  expect "a second write seat in a busy worktree exits 2" test "$status" -eq 2
  status=0
  printf '%s\n' 999999999 >"$lock/pid"
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief "$work/brief.md" --report "$work/stale.md" >/dev/null 2>&1 || status=$?
  expect "a stale write lock from a dead process is replaced" test "$status" -eq 0
  expect "the write lock is released after the run" test ! -e "$lock"

  status=0
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief <(printf 'Piped fixture task.\n') --report "$work/piped.md" >/dev/null 2>&1 || status=$?
  expect "a piped brief reaches the worker" bash -c '[[ "$0" == 0 ]] && grep -qF "Piped fixture task." "$1"' "$status" "$logs/stdin"
  status=0
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief <(printf '  \n') --report "$work/empty.md" >/dev/null 2>&1 || status=$?
  expect "an empty piped brief exits 2" test "$status" -eq 2

  status=0
  mkdir -p "$repo/sub"
  CLAUDE_WORKER_SANDBOX_COMMANDS="bash" run_worker run --model deepseek-v4.1-flash --dir "$repo/sub" --brief "$work/brief.md" --report "$work/judge.md" --readonly >/dev/null 2>&1 || status=$?
  expect "readonly run exits 0 when the sandbox commands exist" test "$status" -eq 0
  expect "readonly run uses dontAsk and keeps Bash without edit tools" bash -c \
    'grep -qx dontAsk "$0" && grep -qx "Read,Glob,Grep,Bash" "$0" && ! grep -qx acceptEdits "$0" && ! grep -qE "(^|,)(Edit|Write)(,|$)" "$0"' "$logs/argv"
  expect "readonly run turns on a fail-closed sandbox that denies writes to the checkout and its Git dir" python3 -B -c '
import json, os, sys
argv = open(sys.argv[1]).read().splitlines()
settings = json.loads(argv[argv.index("--settings") + 1])["sandbox"]
assert settings["enabled"] is True and settings["failIfUnavailable"] is True
assert settings["allowUnsandboxedCommands"] is False
deny = settings["filesystem"]["denyWrite"]
real = os.path.realpath
assert real(sys.argv[2]) in map(real, deny), deny
assert real(sys.argv[2] + "/.git") in map(real, deny), deny' "$logs/argv" "$repo"
  expect "readonly run turns off hooks, which run outside the sandbox" python3 -B -c '
import json, sys
argv = open(sys.argv[1]).read().splitlines()
assert json.loads(argv[argv.index("--settings") + 1])["disableAllHooks"] is True' "$logs/argv"
  expect "readonly run offers only the read tools and Bash, and no MCP server" bash -c \
    'grep -A1 -x -- --tools "$0" | grep -qx "Read,Glob,Grep,Bash" && grep -qx -- --strict-mcp-config "$0"' "$logs/argv"
  expect "readonly meta records the sandbox" python3 -B -c '
import json, sys
m = json.load(open(sys.argv[1]))
assert m["mode"] == "readonly" and m["sandbox"] is True' "$work/judge.md.meta.json"
  status=0
  CLAUDE_WORKER_SANDBOX_COMMANDS="bash" run_worker run --model deepseek-v4.1-flash --dir "$work" --brief "$work/brief.md" --report "$work/judge-linked.md" --readonly >/dev/null 2>&1 || status=$?
  expect "a readonly seat in a linked worktree denies writes to the shared Git dir" python3 -B -c '
import json, os, sys
argv = open(sys.argv[1]).read().splitlines()
deny = list(map(os.path.realpath, json.loads(argv[argv.index("--settings") + 1])["sandbox"]["filesystem"]["denyWrite"]))
assert os.path.realpath(sys.argv[2]) in deny and os.path.realpath(sys.argv[3] + "/.git") in deny, deny' "$logs/argv" "$work" "$repo"
  status=0
  CLAUDE_WORKER_SANDBOX_COMMANDS="claude-worker-fixture-missing-command" run_worker run --model deepseek-v4.1-flash --dir "$repo" --brief "$work/brief.md" --report "$work/nosandbox.md" --readonly >/dev/null 2>&1 || status=$?
  expect "a readonly run without the sandbox commands exits 3" test "$status" -eq 3
  expect "a write run gets no sandbox settings" bash -c '! grep -qx -- --settings "$0"' "$logs/argv.write"

  status=0
  echo error >"$dir/mode"; run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/err.md" >/dev/null 2>&1 || status=$?
  expect "an is_error result exits 1" test "$status" -eq 1
  status=0
  echo crash >"$dir/mode"; run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/crash.md" >/dev/null 2>&1 || status=$?
  expect "a crashed worker exits 1 and writes a placeholder report" bash -c \
    '[[ "$0" == 1 ]] && grep -q "worker produced no report" "$1"' "$status" "$work/crash.md"
  status=0
  run_worker run --model worker/nope --dir "$work" --brief "$work/brief.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "an unknown alias exits 2" test "$status" -eq 2
  status=0
  run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/missing.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "a missing brief exits 2" test "$status" -eq 2
  status=0
  echo ok >"$dir/mode"
  PROFILE_OVERRIDE="$dir/absent" run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "a missing worker profile exits 3" test "$status" -eq 3
  status=0
  KEY_FILE_OVERRIDE=/nonexistent run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/x.md" >/dev/null 2>&1 || status=$?
  expect "a missing provider key exits 3" test "$status" -eq 3

  echo ok >"$dir/mode"
  status=0
  mkdir -p "$dir/caller"
  (cd "$dir/caller" && run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report relative.md >/dev/null 2>&1) || status=$?
  expect "a relative --report resolves from the caller directory, not from --dir" bash -c \
    '[[ "$0" == 0 ]] && grep -qF "**Result**: done." "$1/relative.md" && [[ -s "$1/relative.md.raw.json" ]]' "$status" "$dir/caller"

  status=0
  KEY_FILE_OVERRIDE="$home/.config/ai-memory/env" run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/keyfile.md" >/dev/null 2>&1 || status=$?
  expect "the key-file override reaches the worker, so apiKeyHelper reads the same file" bash -c \
    '[[ "$0" == 0 ]] && grep -qx "CLAUDE_WORKER_KEY_ENV_FILE=$1" "$2"' "$status" "$home/.config/ai-memory/env" "$logs/env"

  status=0
  KEY_FILE_OVERRIDE=/nonexistent OPENCODE_API_KEY=sk-env-fixture run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/envkey.md" >/dev/null 2>&1 || status=$?
  expect "a key in the environment reaches the worker, so apiKeyHelper reads it there too" bash -c \
    '[[ "$0" == 0 ]] && grep -qx "OPENCODE_API_KEY=sk-env-fixture" "$1"' "$status" "$logs/env"
  expect "the worker gets the worker profile path for the network-secret marker" grep -qx "CLAUDE_WORKER_CONFIG_DIR=$profile" "$logs/env"
  status=0
  HTTPS_PROXY=http://127.0.0.1:3128 no_proxy=localhost NODE_EXTRA_CA_CERTS=/etc/proxy-ca.crt \
    run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/proxy.md" >/dev/null 2>&1 || status=$?
  expect "the proxy and CA variables reach the worker, so a network secret is injected" bash -c \
    '[[ "$0" == 0 ]] && grep -qx "HTTPS_PROXY=http://127.0.0.1:3128" "$1" && grep -qx "no_proxy=localhost" "$1" &&
      grep -qx "NODE_EXTRA_CA_CERTS=/etc/proxy-ca.crt" "$1"' "$status" "$logs/env"
  status=0
  run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/nokeyvar.md" >/dev/null 2>&1 || status=$?
  expect "without a key variable, none is passed to the worker" bash -c '[[ "$0" == 0 ]] && ! grep -q "^OPENCODE_API_KEY=" "$1"' "$status" "$logs/env"
  status=0
  : >"$profile/network-secret"
  KEY_FILE_OVERRIDE=/nonexistent run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/netsecret.md" >/dev/null 2>&1 || status=$?
  rm -f "$profile/network-secret"
  expect "network-secret mode passes the key preflight without a key file" test "$status" -eq 0

  local started elapsed no_timeout_path
  status=0
  echo sleep >"$dir/mode"
  no_timeout_path="$(timeout_free_path "$dir/notimeout")"
  started="$(date +%s)"
  PATH="$no_timeout_path" run_worker run --model worker/glm-5.3 --dir "$work" --brief "$work/brief.md" --report "$work/slow.md" --timeout 1 >/dev/null 2>&1 || status=$?
  elapsed=$(( $(date +%s) - started ))
  echo ok >"$dir/mode"
  expect "the fixture PATH has no timeout executable" bash -c '! PATH="$0" type -P timeout >/dev/null' "$no_timeout_path"
  expect "--timeout stops a stalled worker without a timeout executable on PATH (exit $status, ${elapsed}s)" bash -c \
    '[[ "$0" == 1 && "$1" -lt 10 ]]' "$status" "$elapsed"

  local ledger_home="$dir/ledger-home" n
  mkdir -p "$ledger_home"
  # A stress check: the header race window is small, so this guards the
  # invariant but may pass by chance against a racy writer.
  for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
    env HOME="$home" CLAUDE_WORKER_CONFIG_DIR="$profile" XDG_STATE_HOME="$ledger_home" \
      CLAUDE_WORKER_CLAUDE_BIN="$dir/claude" CLAUDE_WORKER_SANDBOX_COMMANDS=bash \
      "$REPO_DIR/bin/claude-worker" run --model worker/glm-5.3 --dir "$repo" --brief "$work/brief.md" \
      --report "$work/parallel-$n.md" --readonly >/dev/null 2>&1 &
  done
  wait
  expect "parallel completions write one ledger header and twelve rows" bash -c \
    '[[ "$(grep -c "^utc	" "$0")" == 1 && "$(grep -vc "^utc	" "$0")" == 12 ]]' "$ledger_home/claude-worker/runs.tsv"

  expect "usage aggregates the ledger" bash -c \
    'env HOME="$0" XDG_STATE_HOME="$0/.local/state" "$1/bin/claude-worker" usage | grep -q "^worker/glm-5.3"' "$home" "$REPO_DIR"
  expect "models names the provider and lists the roster with the worker/ prefix" bash -c \
    'out="$("$0/bin/claude-worker" models)"; grep -q "^provider: opencode-go" <<<"$out" && grep -q "^worker/kimi-k3.1	kimi-k3.1-pro	kimi" <<<"$out"' "$REPO_DIR"
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
      configure_worker_profile
      merge_claude_shell_block
      configure_bash_login_env
    ' "$REPO_DIR" >/dev/null
  }
  snapshot() {
    (cd "$home" && find . -type f -o -type l | sort | while read -r f; do
      if [[ -L "$f" ]]; then printf '%s -> %s\n' "$f" "$(readlink "$f")"; else sha256sum "$f"; fi
    done)
  }

  mkdir -p "$home/.claude"
  printf '%s\n' '# my own instructions' >"$home/.claude/CLAUDE.md"
  expect "offline apply functions succeed" run_offline_apply
  expect "a differing managed file is backed up before it is replaced" bash -c \
    'set -- "$0"/.claude/CLAUDE.md.bak-*; [[ $# -eq 1 && -f "$1" ]] && grep -qx "# my own instructions" "$1"' "$home"
  expect "~/.claude/CLAUDE.md is the repository CLAUDE.md plus the RTK import" equals_source_with_rtk_import "$REPO_DIR/CLAUDE.md" "$home/.claude/CLAUDE.md"
  expect "managed rules are installed" bash -c \
    'for r in pstack-models.md pstack-workers.md; do cmp -s "$0/claude/rules/$r" "$1/.claude/rules/$r" || exit 1; done' \
    "$REPO_DIR" "$home"
  expect "main settings select Opus and allow claude-worker runs" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["model"] == "opus" and "Bash(claude-worker run *)" in d["permissions"]["allow"]' "$home/.claude/settings.json"
  expect "worker settings use provider.env and claude-worker-key" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["apiKeyHelper"] == sys.argv[2]
assert d["env"]["ANTHROPIC_BASE_URL"] == "https://opencode.ai/inference/go/anthropic"
assert d["env"]["ANTHROPIC_DEFAULT_HAIKU_MODEL"] == "deepseek-v4.1-flash"
assert d["env"]["CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS"] == "1"' "$home/.claude-worker/settings.json" "$REPO_DIR/bin/claude-worker-key"
  expect "main settings enable the built-in you-should-know mod" python3 -B -c '
import json, sys
d = json.load(open(sys.argv[1]))
assert d["enabledPlugins"]["cc-plugin-you-should-know@builtin"] is True' "$home/.claude/settings.json"
  expect "worker settings do not enable the you-should-know mod" file_lacks "$home/.claude-worker/settings.json" 'you-should-know'
  expect "main settings carry no worker provider routing" file_lacks "$home/.claude/settings.json" 'ANTHROPIC_BASE_URL'
  expect "~/.claude-worker/CLAUDE.md is the worker contract plus the RTK import" equals_source_with_rtk_import "$REPO_DIR/claude/worker/contract.md" "$home/.claude-worker/CLAUDE.md"
  expect "claude-worker and claude-worker-key are linked into ~/.local/bin" bash -c \
    '[[ "$(readlink "$0/claude-worker")" == "$1/claude-worker" && "$(readlink "$0/claude-worker-key")" == "$1/claude-worker-key" ]]' \
    "$home/.local/bin" "$REPO_DIR/bin"
  expect "bash aliases gain the Claude block and lose the OpenCode block" bash -c \
    'grep -qF "Claude Code ai-memory wrapper >>>" "$0" && ! grep -qF "opencode() { :; }" "$0"' "$home/.bash_aliases"
  expect "login profile loads aliases and ~/.profile" bash -c \
    'grep -qF "source \"\$HOME/.bash_aliases\"" "$0" && grep -qF "source \"\$HOME/.profile\"" "$0" && ! grep -q opencode "$0"' \
    "$home/.bash_profile"
  expect "login profile does not export the ai-memory environment file" file_lacks "$home/.bash_profile" '.config/ai-memory'

  first="$(snapshot)"
  run_offline_apply
  second="$(snapshot)"
  expect "offline apply functions are idempotent" test "$first" == "$second"
  [[ "$first" == "$second" ]] || diff <(printf "%s\n" "$first") <(printf "%s\n" "$second") || true
}

# --- ai-memory environment file fixtures ----------------------------------

ai_memory_env_fixtures() {
  printf '\n== ai-memory environment file fixtures\n'
  local home="$FIXTURE_ROOT/ai-memory-env-home" env_file output before
  local secret="sk-fixture-secret-0123456789"
  env_file="$home/.config/ai-memory/env"

  check_env() {
    env -i HOME="$home" PATH="$PATH" bash -c '
      set -Eeuo pipefail
      source "$0/apply.sh"
      check_ai_memory_env_file
    ' "$REPO_DIR" 2>&1
  }

  mkdir -p "$home"
  check_env_quiet() { check_env >/dev/null; }
  expect "a missing environment file is created" check_env_quiet
  expect "the created environment file is empty and private" bash -c \
    '[[ -f "$0" && ! -s "$0" && "$(stat -c %a "$0" 2>/dev/null || stat -f %Lp "$0")" == 600 ]]' "$env_file"

  mkdir -p "$(dirname "$env_file")"
  printf 'AI_MEMORY_LLM_PROVIDER=opencode\nAI_MEMORY_LLM_MODEL=deepseek-v4.1-flash\nOPENCODE_API_KEY=%s\n' "$secret" >"$env_file"
  chmod 600 "$env_file"
  before="$(sha256sum "$env_file")"
  output="$(check_env || printf "check_ai_memory_env_file failed\n")"
  expect "a configured LLM is reported as enabled" grep -qF 'ai-memory LLM enabled: provider opencode, model deepseek-v4.1-flash' <<<"$output"
  expect "apply never rewrites the operator environment file" test "$before" == "$(sha256sum "$env_file")"
  expect "the API key never reaches apply output" bash -c '! grep -qF "$0" <<<"$1"' "$secret" "$output"

  printf 'AI_MEMORY_LLM_PROVIDER=opencode\nAI_MEMORY_LLM_MODEL=deepseek-v4.1-flash\n' >"$env_file"
  output="$(check_env || printf "check_ai_memory_env_file failed\n")"
  expect "a missing provider key is reported by name" grep -qF 'ai-memory LLM disabled: OPENCODE_API_KEY is not set' <<<"$output"

  : >"$env_file"
  output="$(check_env || printf "check_ai_memory_env_file failed\n")"
  expect "an empty file reports both unset names" grep -qF 'ai-memory LLM disabled: AI_MEMORY_LLM_PROVIDER, AI_MEMORY_LLM_MODEL are not set' <<<"$output"

  printf '%s\n' 'AGENTS_AI_MEMORY_LLM_ENABLED=false' 'DOTFILES_AI_MEMORY_LLM_PROFILE=x' \
    'AGENTS_AI_MEMORY_REMOTE_MODE=false' 'AI_MEMORY_SERVER_URL=http://127.0.0.1:49374' >"$env_file"
  before="$(sha256sum "$env_file")"
  output="$(check_env || printf "check_ai_memory_env_file failed\n")"
  expect "retired names are reported" bash -c \
    'for n in AGENTS_AI_MEMORY_LLM_ENABLED DOTFILES_AI_MEMORY_LLM_PROFILE AGENTS_AI_MEMORY_REMOTE_MODE AI_MEMORY_SERVER_URL; do grep -qF "$n" <<<"$0" || exit 1; done' "$output"
  expect "retired names are reported, not removed" test "$before" == "$(sha256sum "$env_file")"
}

# --- worker key source fixtures ---------------------------------------------

key_source_fixtures() {
  printf '\n== worker key source fixtures\n'
  local dir="$FIXTURE_ROOT/key-sources" home secret="sk-key-source-fixture-0123456789"
  home="$dir/home"
  mkdir -p "$home/.claude-worker"
  : >"$home/.claude-worker/network-secret"
  # Key resolution: key file, then the environment variable, then the
  # network-secret placeholder.
  printf '%s\n' '#!/usr/bin/env bash' "env -i HOME=\"$home\" PATH=\"\$PATH\" \"\$@\" \"$REPO_DIR/bin/claude-worker-key\"" >"$dir/key.sh"
  chmod +x "$dir/key.sh"
  expect "without a key file, the key comes from OPENCODE_API_KEY" bash -c '[[ "$("$0" OPENCODE_API_KEY="$1" 2>/dev/null)" == "$1" ]]' "$dir/key.sh" "$secret"
  expect "without a key file or variable, network-secret mode prints a placeholder" bash -c \
    '[[ "$("$0" 2>/dev/null)" == network-secret-placeholder ]]' "$dir/key.sh"
  mkdir -p "$home/.config/ai-memory"
  printf 'OPENCODE_API_KEY=%s-file\n' "$secret" >"$home/.config/ai-memory/env"
  expect "the key file wins over the variable and the placeholder" bash -c \
    '[[ "$("$0" OPENCODE_API_KEY="$1" 2>/dev/null)" == "$1-file" ]]' "$dir/key.sh" "$secret"
  rm -f "$home/.config/ai-memory/env" "$home/.claude-worker/network-secret"
  expect "with no source at all, the key helper exits 1" bash -c '! "$0" >/dev/null 2>&1' "$dir/key.sh"
}

# --- cloud profile fixtures -------------------------------------------------

cloud_fixtures() {
  printf '\n== cloud profile fixtures\n'
  local dir="$FIXTURE_ROOT/cloud" home bin output
  home="$dir/home"; bin="$dir/usr-local-bin"
  mkdir -p "$home" "$bin"

  run_cloud() {
    env -i HOME="$home" PATH="$PATH" CLOUD_BIN_DIR="$bin" bash -c '
      set -Eeuo pipefail
      source "$0/apply.sh"
      calls=()
      check_cloud_prerequisites() { calls+=(prerequisites); }
      install_claude_code() { calls+=("claude-code min $CLAUDE_MIN_VERSION"); }
      install_rtk() { calls+=(rtk); }
      wire_rtk_to_claude_code() { calls+=("rtk-wire $1"); }
      install_pstack_plugin() { calls+=(pstack); }
      install_ai_memory() { calls+=(AI-MEMORY); }
      setup_ai_memory() { calls+=(AI-MEMORY); }
      merge_claude_shell_block() { calls+=(SHELL-BLOCK); }
      main --cloud >"$1/cloud.log"
      printf "%s\n" "${calls[@]}"
    ' "$REPO_DIR" "$dir" 2>&1
  }
  output="$(run_cloud || printf "apply.sh --cloud failed\n")"
  expect "apply.sh --cloud succeeds" bash -c '! grep -qF "apply.sh --cloud failed" <<<"$0"' "$output"
  expect "the cloud profile installs Claude Code, RTK, pstack, and wires RTK to both profiles" bash -c \
    'for c in prerequisites "claude-code min 2.1.259" rtk pstack "rtk-wire $1/.claude" "rtk-wire $1/.claude-worker"; do grep -qxF "$c" <<<"$0" || exit 1; done' "$output" "$home"
  expect "the cloud profile skips ai-memory and the Bash wrapper" bash -c \
    '! grep -qE "AI-MEMORY|SHELL-BLOCK" <<<"$0"' "$output"
  expect "the cloud profile installs the instructions and rules" bash -c \
    'equals() { cmp -s <(cat "$1"; printf "\n@RTK.md\n") "$2"; }; equals "$0/CLAUDE.md" "$1/.claude/CLAUDE.md" && cmp -s "$0/claude/rules/pstack-models.md" "$1/.claude/rules/pstack-models.md"' "$REPO_DIR" "$home"
  expect "the cloud profile does not enable the you-should-know mod" file_lacks "$home/.claude/settings.json" 'you-should-know'
  expect "the cloud profile allows claude-worker runs" grep -qF 'Bash(claude-worker run *)' "$home/.claude/settings.json"
  expect "the cloud profile links claude-worker into the cloud bin directory" bash -c \
    '[[ "$(readlink "$0/claude-worker")" == "$1/claude-worker" && "$(readlink "$0/claude-worker-key")" == "$1/claude-worker-key" ]]' "$bin" "$REPO_DIR/bin"
  expect "the cloud profile turns on the network-secret key mode" test -f "$home/.claude-worker/network-secret"
  expect "the cloud profile does not report a missing key" file_lacks "$dir/cloud.log" 'API key not found'
  expect "cloud/setup.sh is valid Bash and runs apply.sh --cloud" bash -c \
    'bash -n "$0/cloud/setup.sh" && grep -qF "apply.sh\" --cloud" "$0/cloud/setup.sh"' "$REPO_DIR"
  expect "apply.sh rejects an unknown option before it changes anything" bash -c \
    'out="$(env -i HOME="$1" PATH="$PATH" bash "$0/apply.sh" --bogus 2>&1)"; [[ $? -ne 0 ]] && grep -qF "Unknown option: --bogus" <<<"$out"' "$REPO_DIR" "$dir/bogus-home"

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

  printf '%s\n' '#!/usr/bin/env bash' 'printf "%s\n" "$@" >"$NATIVE_LOG"' >"$dir/bin/claude"
  chmod +x "$dir/bin/claude"
  native_case() {
    rm -f "$dir/log" "$dir/native"
    env -i HOME="$dir" PATH="$dir/bin:/usr/bin:/bin" WRAPPER_LOG="$dir/log" NATIVE_LOG="$dir/native" bash -c \
      'source "$0"; claude "$@"' "$REPO_DIR/shell/claude.bash" "$@" >/dev/null 2>&1
  }
  expect "the bypass comment and the case pattern name the same subcommands" bash -c '
    comment="$(sed -n "s/^ *# native subcommands: //p" "$0" | tr " " "\n" | sort)"
    pattern="$(sed -n "/# native subcommands:/{n;p}" "$0" | sed "s/).*//; s/^ *//" | tr "|" "\n" | grep -v "^-" | sort)"
    [[ -n "$comment" && "$comment" == "$pattern" ]]' "$REPO_DIR/shell/claude.bash"
  native_case plugin list
  expect "a CLI subcommand runs native claude, not a managed session" bash -c \
    '[[ ! -e "$0" && "$(tr "\n" " " <"$1")" == "plugin list " ]]' "$dir/log" "$dir/native"
  native_case --version
  expect "claude --version runs native claude" bash -c \
    '[[ ! -e "$0" && "$(cat "$1")" == "--version" ]]' "$dir/log" "$dir/native"
  native_case -p "plugin list"
  expect "a print-mode prompt stays a managed session" bash -c \
    '[[ ! -e "$1" && "$(tr "\n" "|" <"$0")" == "run|claude|-p|plugin list|" ]]' "$dir/log" "$dir/native"
}

# --- RTK install fixtures ----------------------------------------------------

# A fake rtk that passes the rewrite compatibility check and reports a version.
ai_memory_release_fixtures() {
  printf '\n== ai-memory release bundle fixtures\n'
  local dir="$FIXTURE_ROOT/ai-memory-release" bundle archive sha output
  bundle="$dir/bundle"
  mkdir -p "$bundle/hooks/claude-code" "$dir/bin" "$dir/home"
  printf '%s\n' '#!/usr/bin/env bash' 'printf "ai-memory 3.3.1\n"' >"$bundle/ai-memory"
  chmod +x "$bundle/ai-memory"
  : >"$bundle/hooks/claude-code/session-start.sh"
  archive="$dir/ai-memory.tar.gz"
  tar -czf "$archive" -C "$bundle" .
  sha="$(sha256sum "$archive" | cut -d' ' -f1)"
  # The fake curl writes the fixture archive to the --output path.
  cat >"$dir/bin/curl" <<FAKE
#!/usr/bin/env bash
while [[ \$# -gt 0 ]]; do
  if [[ "\$1" == --output ]]; then cp "$archive" "\$2"; exit 0; fi
  shift
done
exit 1
FAKE
  chmod +x "$dir/bin/curl"

  run_release() {
    env -i HOME="$dir/home" PATH="$dir/home/.local/bin:$dir/bin:/usr/bin:/bin" bash -c '
      set -Eeuo pipefail
      source "$0/apply.sh"
      ai_memory_platform() { printf "Linux\tx86_64\n"; }
      AI_MEMORY_LINUX_X86_64_SHA256="$1"
      install_ai_memory_release
      ai-memory --version
    ' "$REPO_DIR" "$1" 2>&1
  }

  output="$(run_release "$sha" || printf 'release install failed\n')"
  expect "Linux installs the verified release bundle and links ai-memory" grep -qx "ai-memory 3.3.1" <<<"$output"
  expect "the bundle keeps the Claude Code hooks next to the linked binary" bash -c \
    '[[ -L "$0/.local/bin/ai-memory" && -d "$(dirname "$(readlink -f "$0/.local/bin/ai-memory")")/hooks/claude-code" ]]' "$dir/home"
  rm -rf "$dir/home"; mkdir -p "$dir/home"
  output="$(run_release 0000000000000000000000000000000000000000000000000000000000000000 || true)"
  expect "a release archive with the wrong digest is refused" bash -c \
    'grep -qF "digest did not match" <<<"$0" && [[ ! -e "$1/.local/bin/ai-memory" ]]' "$output" "$dir/home"

  # Source selection on Linux: the AUR with yay, the release bundle without.
  select_source() {
    env -i HOME="$dir/home" PATH="$1:/usr/bin:/bin" bash -c '
      set -Eeuo pipefail
      source "$0/apply.sh"
      agent_stack_platform() { printf "Linux\n"; }
      have() { [[ "$1" == yay ]] && type -P yay >/dev/null; }
      install_aur_command() { printf "AUR\n"; }
      install_ai_memory_release() { printf "RELEASE\n"; }
      verify_native_ai_memory() { :; }
      require_minimum_version() { :; }
      install_ai_memory
    ' "$REPO_DIR" 2>&1
  }
  mkdir -p "$dir/yay"
  printf '%s\n' '#!/usr/bin/env bash' >"$dir/yay/yay"; chmod +x "$dir/yay/yay"
  expect "Linux with yay uses the AUR package" grep -qx AUR <<<"$(select_source "$dir/yay")"
  expect "Linux without yay uses the release bundle" grep -qx RELEASE <<<"$(select_source "$dir/bin")"
}

make_fake_rtk() {
  local path="$1" version="$2"
  {
    printf '%s\n' '#!/usr/bin/env bash' "version='$version'"
    cat <<'FAKE'
case "${1:-}" in
  --version) printf 'rtk %s\n' "$version" ;;
  rewrite) printf 'rtk %s\n' "$2" ;;
  gain) : ;;
esac
FAKE
  } >"$path"
  chmod +x "$path"
}

rtk_fixtures() {
  printf '\n== RTK install fixtures\n'
  local dir="$FIXTURE_ROOT/rtk"
  mkdir -p "$dir/bin" "$dir/home/.local/bin"
  # The fake curl prints an installer script; sh runs it, and it installs an
  # rtk that reports the version the installer was asked for.
  cat >"$dir/bin/curl" <<FAKE
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"$dir/curl.log"
cat <<'SCRIPT'
version="\${RTK_VERSION#v}"
printf '%s\n' '#!/usr/bin/env bash' "version='\$version'" \
  'case "\${1:-}" in --version) printf "rtk %s\n" "\$version" ;; rewrite) printf "rtk %s\n" "\$2" ;; esac' \
  >"\$HOME/.local/bin/rtk"
chmod +x "\$HOME/.local/bin/rtk"
SCRIPT
FAKE
  chmod +x "$dir/bin/curl"

  run_install_rtk() {
    env -i HOME="$dir/home" PATH="$dir/home/.local/bin:$dir/bin:/usr/bin:/bin" bash -c '
      set -Eeuo pipefail
      source "$0/apply.sh"
      install_rtk
      rtk --version
    ' "$REPO_DIR" 2>&1
  }

  local pinned output
  pinned="$(sed -n 's/^RTK_VERSION="\${RTK_VERSION:-v\(.*\)}"$/\1/p' "$REPO_DIR/apply.sh")"

  make_fake_rtk "$dir/home/.local/bin/rtk" 0.48.0
  : >"$dir/curl.log"
  output="$(run_install_rtk)" || true
  expect "an older compatible RTK is upgraded to the pinned release" bash -c \
    '[[ "$(tail -n 1 <<<"$0")" == "rtk $1" ]] && grep -q "rtk-ai/rtk/v$1/install.sh" "$2"' \
    "$output" "$pinned" "$dir/curl.log"

  make_fake_rtk "$dir/home/.local/bin/rtk" "$pinned"
  : >"$dir/curl.log"
  output="$(run_install_rtk)" || true
  expect "a current compatible RTK is kept without a download" bash -c \
    '[[ "$(tail -n 1 <<<"$0")" == "rtk $1" && ! -s "$2" ]]' "$output" "$pinned" "$dir/curl.log"

  make_fake_rtk "$dir/home/.local/bin/rtk" 9.9.9
  : >"$dir/curl.log"
  output="$(run_install_rtk)" || true
  expect "a newer compatible RTK is kept, never downgraded" bash -c \
    '[[ "$(tail -n 1 <<<"$0")" == "rtk 9.9.9" && ! -s "$1" ]]' "$output" "$dir/curl.log"
}

# --- Machine checks ---------------------------------------------------------

machine_checks() {
  printf '\n== Machine checks (this host)\n'
  local home="$REAL_HOME"
  PATH="$home/.local/bin:$PATH"

  expect "claude is installed" bash -c 'type -P claude >/dev/null'
  expect "the you-should-know mod is enabled in the main profile" python3 -B -c '
import json, sys
assert json.load(open(sys.argv[1]))["enabledPlugins"]["cc-plugin-you-should-know@builtin"] is True' "$home/.claude/settings.json"
  expect "pstack plugin is installed" bash -c 'claude plugin list 2>/dev/null | grep -q "pstack@cursor-plugins"'
  expect "~/.claude/CLAUDE.md is the repository CLAUDE.md plus the RTK import" equals_source_with_rtk_import "$REPO_DIR/CLAUDE.md" "$home/.claude/CLAUDE.md"
  expect "~/.claude-worker/CLAUDE.md is the worker contract plus the RTK import" equals_source_with_rtk_import "$REPO_DIR/claude/worker/contract.md" "$home/.claude-worker/CLAUDE.md"
  expect "managed rules are current" bash -c \
    'for r in pstack-models.md pstack-workers.md; do cmp -s "$0/claude/rules/$r" "$1/.claude/rules/$r" || exit 1; done' \
    "$REPO_DIR" "$home"
  expect "ai-memory routing rule exists" test -s "$home/.claude/rules/ai-memory.md"
  expect "ai-memory hooks are in the main profile" file_contains "$home/.claude/settings.json" 'ai-memory'
  expect "RTK hook is in the main profile" file_contains "$home/.claude/settings.json" 'rtk'
  expect "RTK hook is in the worker profile" file_contains "$home/.claude-worker/settings.json" 'rtk'
  expect "ai-memory hooks stay out of the worker profile" file_lacks "$home/.claude-worker/settings.json" 'ai-memory'
  expect "RTK did not set a proxy base URL in the main profile" file_lacks "$home/.claude/settings.json" 'ANTHROPIC_BASE_URL'
  expect "claude-worker is on PATH" bash -c 'command -v claude-worker >/dev/null'
  expect "RTK is the pinned release or newer" bash -c \
    'source "$0/lib/common.bash"; (require_minimum_version rtk "$(sed -n "s/^RTK_VERSION=\"\${RTK_VERSION:-v\(.*\)}\"$/\1/p" "$0/apply.sh")") >/dev/null 2>&1' "$REPO_DIR"
  expect "ai-memory is the pinned release or newer" bash -c \
    'source "$0/lib/common.bash"; (require_minimum_version ai-memory "$(sed -n "s/^AI_MEMORY_MIN_VERSION=\"\${AI_MEMORY_MIN_VERSION:-\(.*\)}\"$/\1/p" "$0/apply.sh")") >/dev/null 2>&1' "$REPO_DIR"
  expect "ai-memory service answers" bash -c 'ai-memory status --json >/dev/null 2>&1'
  expect "the wrapper bypass list matches the installed claude subcommands" bash -c '
    want="$("$(type -P claude)" --help 2>/dev/null | sed -n "/^Commands:/,\$p" | grep -E "^  [a-z]" | awk "{print \$1}" | tr "|" "\n" | sort -u)"
    have="$(sed -n "s/^ *# native subcommands: //p" "$0" | tr " " "\n" | sort -u)"
    [[ -n "$want" && "$want" == "$have" ]]' "$REPO_DIR/shell/claude.bash"
  expect "bash aliases carry the Claude block" file_contains "$home/.bash_aliases" 'Claude Code ai-memory wrapper >>>'
  printf '\nRun `claude-worker doctor` (and `claude-worker doctor --live`) to check the worker provider.\n'
}

static_checks
helper_fixtures
worker_fixtures
apply_fixtures
key_source_fixtures
cloud_fixtures
ai_memory_env_fixtures
ai_memory_release_fixtures
wrapper_fixtures
rtk_fixtures
if [[ "$repo_only" == false ]]; then
  machine_checks
fi

printf '\n%s passed, %s failed\n' "$passes" "$failures"
[[ "$failures" -eq 0 ]]
