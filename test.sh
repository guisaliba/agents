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
  expect "the managed CLAUDE.md files end with the RTK import" bash -c \
    'for f in "$0/CLAUDE.md" "$0/claude/worker/CLAUDE.md"; do [[ "$(tail -n 1 "$f")" == "@RTK.md" ]] || exit 1; done' "$REPO_DIR"
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
    '! grep -rIn -E "go-worker|go-key|claude-go|(^|[^a-z-])go/[a-z]" "$0/apply.sh" "$0/lib" "$0/bin" "$0/shell" "$0/claude/rules" "$0/claude/worker/CLAUDE.md"' "$REPO_DIR"
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
esac
FAKE
  } >"$path"
  chmod +x "$path"
}

worker_fixtures() {
  printf '\n== claude-worker-key and claude-worker fixtures\n'
  local dir="$FIXTURE_ROOT/worker"
  local home="$dir/home" profile="$dir/home/.claude-worker" logs="$dir/logs" work="$dir/work"
  local secret="sk-fixture-$$-do-not-leak"
  mkdir -p "$home/.config/ai-memory" "$profile" "$logs" "$work"
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

  status=0
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief <(printf 'Piped fixture task.\n') --report "$work/piped.md" >/dev/null 2>&1 || status=$?
  expect "a piped brief reaches the worker" bash -c '[[ "$0" == 0 ]] && grep -qF "Piped fixture task." "$1"' "$status" "$logs/stdin"
  status=0
  run_worker run --model worker/kimi-k3.1 --dir "$work" --brief <(printf '  \n') --report "$work/empty.md" >/dev/null 2>&1 || status=$?
  expect "an empty piped brief exits 2" test "$status" -eq 2

  run_worker run --model deepseek-v4.1-flash --dir "$work" --brief "$work/brief.md" --report "$work/judge.md" --readonly >/dev/null 2>&1 || true
  expect "readonly run uses dontAsk and keeps Bash without edit tools" bash -c \
    'grep -qx dontAsk "$0" && grep -qx "Read,Glob,Grep,Bash" "$0" && ! grep -qx acceptEdits "$0" && ! grep -qE "(^|,)(Edit|Write)(,|$)" "$0"' "$logs/argv"

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
  expect "~/.claude/CLAUDE.md is a copy of the repository CLAUDE.md" cmp -s "$REPO_DIR/CLAUDE.md" "$home/.claude/CLAUDE.md"
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
  expect "worker CLAUDE.md is installed" cmp -s "$REPO_DIR/claude/worker/CLAUDE.md" "$home/.claude-worker/CLAUDE.md"
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
  expect "~/.claude/CLAUDE.md equals the repository CLAUDE.md" cmp -s "$REPO_DIR/CLAUDE.md" "$home/.claude/CLAUDE.md"
  expect "~/.claude-worker/CLAUDE.md equals the worker contract" cmp -s "$REPO_DIR/claude/worker/CLAUDE.md" "$home/.claude-worker/CLAUDE.md"
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
ai_memory_env_fixtures
wrapper_fixtures
if [[ "$repo_only" == false ]]; then
  machine_checks
fi

printf '\n%s passed, %s failed\n' "$passes" "$failures"
[[ "$failures" -eq 0 ]]
