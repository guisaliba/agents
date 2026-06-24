#!/usr/bin/env bash
set -Eeuo pipefail

event="${1:-session-start}"
format="${2:-text}"

ensure_caveman_config() {
  python3 - <<'PY'
import json
import os
from pathlib import Path

base = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config")) / "caveman"
base.mkdir(parents=True, exist_ok=True)
path = base / "config.json"

data = {}
if path.exists() and not path.is_symlink():
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = {}

data["defaultMode"] = "ultra"
tmp = path.with_name(f".{path.name}.{os.getpid()}.tmp")
tmp.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
tmp.chmod(0o600)
tmp.replace(path)
PY
}

stack_message() {
  local rtk_status="missing"
  
  if command -v rtk >/dev/null 2>&1; then
    rtk_status="available"
  fi

  cat <<EOF
Agent stack active for this session/resume:
- caveman: ultra default, stay concise until user says stop caveman or normal mode.
- rtk: ${rtk_status}; prefer rtk-wrapped shell/tool output when available.
- required skills: caveman, rtk, grill-me, grill-with-docs, find-skills, tdd.
EOF
}

prompt_message() {
  local prompt=""
  if [[ ! -t 0 ]]; then
    local hook_input
    hook_input="$(cat)"
    prompt="$(HOOK_INPUT="$hook_input" python3 - <<'PY'
import json
import os
import sys

try:
    data = json.loads(os.environ.get("HOOK_INPUT", "{}"))
except Exception:
    data = {}

print(str(data.get("prompt", "")))
PY
)"
  fi

  case "${prompt,,}" in
    *"stop caveman"*|*"normal mode"*)
      return 1
      ;;
  esac

  cat <<'EOF'
Per-prompt stack reminder: caveman ultra active; rtk available for compact shell/tool output.
EOF
}

emit() {
  local hook_event="$1"
  local message="$2"

  if [[ "$format" == "claude-json" ]]; then
    HOOK_EVENT="$hook_event" MESSAGE="$message" python3 - <<'PY'
import json
import os

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": os.environ["HOOK_EVENT"],
        "additionalContext": os.environ["MESSAGE"],
        **({"reloadSkills": True} if os.environ["HOOK_EVENT"] == "SessionStart" else {}),
    }
}))
PY
  else
    printf '%s\n' "$message"
  fi
}

case "$event" in
  session-start)
    ensure_caveman_config
    emit "SessionStart" "$(stack_message)"
    ;;
  prompt)
    if message="$(prompt_message)"; then
      emit "UserPromptSubmit" "$message"
    fi
    ;;
  *)
    printf 'unknown event: %s\n' "$event" >&2
    exit 2
    ;;
esac
