#!/usr/bin/env bash
set -Eeuo pipefail

# apply.sh
#
# Deterministic OpenCode setup script.
# Installs OpenCode, RTK, Plannotator, and required skills.
# Installs/updates skills live on every run.
#
# Usage:
#   ./agents/apply.sh
#
# Prerequisites: curl, git, npm, npx, python3.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
RTK_VERSION="${RTK_VERSION:-v0.38.0}"

log() {
  printf '\n==> %s\n' "$*"
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

check_prerequisites() {
  log "Checking prerequisites"
  local missing=()
  for cmd in curl git npm npx python3; do
    if ! have "$cmd"; then
      missing+=("$cmd")
    fi
  done
  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing prerequisites: ${missing[*]}. Install them before running this script."
  fi
  log "All prerequisites present"
}

install_opencode() {
  if have opencode; then
    log "OpenCode already installed, skipping"
    return
  fi

  log "Installing OpenCode"
  curl -fsSL https://opencode.ai/install | bash || die "OpenCode install failed"

  export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  have opencode || die "OpenCode install did not put opencode on PATH"
}

copy_agents_md() {
  log "Copying canonical AGENTS.md to OpenCode global config"

  local src="$DOTFILES_DIR/agents/AGENTS.md"
  [[ -f "$src" ]] || die "Missing canonical agent instructions: $src"

  mkdir -p "$HOME/.config/opencode"
  cp "$src" "$HOME/.config/opencode/AGENTS.md"
}

native_scout_available() {
  local clean_home output
  clean_home="$(mktemp -d)"

  if output="$(
    HOME="$clean_home" \
      OPENCODE_DISABLE_EXTERNAL_SKILLS=1 \
      opencode agent list --pure 2>/dev/null
  )" && [[ "$output" == *$'\nscout (subagent)\n'* ]]; then
    rm -rf "$clean_home"
    return 0
  fi

  rm -rf "$clean_home"
  return 1
}

merge_opencode_json() {
  log "Merging OpenCode opencode.json"

  local config="$HOME/.config/opencode/opencode.json"
  local manage_scout=false
  mkdir -p "$(dirname "$config")"

  if native_scout_available; then
    manage_scout=true
    log "Native Scout subagent available; applying its model override"
  else
    log "Native Scout subagent unavailable; leaving Scout unmanaged"
  fi

  python3 - "$config" "$manage_scout" <<'PY'
import json
import os
import sys

path = sys.argv[1]
manage_scout = sys.argv[2] == "true"
data = {}

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise SystemExit(
            f"ERROR: Invalid JSON in {path} at line {exc.lineno}, "
            f"column {exc.colno}: {exc.msg}. File was not changed."
        )

if not isinstance(data, dict):
    raise SystemExit(
        f"ERROR: Expected a JSON object in {path}, found "
        f"{type(data).__name__}. File was not changed."
    )

data.setdefault("$schema", "https://opencode.ai/config.json")

sol_model = "openai/gpt-5.6-sol"
deepseek_model = "opencode-go/deepseek-v4-flash"
data["model"] = sol_model
data["default_agent"] = "build"

agents = data.get("agent", {})
if not isinstance(agents, dict):
    raise SystemExit(
        f"ERROR: Expected 'agent' to be an object in {path}. File was not changed."
    )

managed_models = {
    "plan": sol_model,
    "general": deepseek_model,
    "explore": deepseek_model,
}
if manage_scout:
    managed_models["scout"] = deepseek_model

for name, model in managed_models.items():
    config = agents.get(name, {})
    if not isinstance(config, dict):
        raise SystemExit(
            f"ERROR: Expected 'agent.{name}' to be an object in {path}. "
            "File was not changed."
        )
    config["model"] = model
    agents[name] = config

if not manage_scout and "scout" in agents:
    scout = agents["scout"]
    if not isinstance(scout, dict):
        raise SystemExit(
            f"ERROR: Expected 'agent.scout' to be an object in {path}. "
            "File was not changed."
        )
    if scout.get("model") == deepseek_model:
        scout.pop("model")
        if not scout:
            agents.pop("scout")

data["agent"] = agents

plugin = "@plannotator/opencode@latest"
plugins = list(data.get("plugin", []))
if isinstance(plugins, str):
    plugins = [plugins]
if plugin not in plugins:
    plugins.append(plugin)
data["plugin"] = plugins

cloudflare_mcps = {
    "cloudflare-api": "https://mcp.cloudflare.com/mcp",
    "cloudflare-docs": "https://docs.mcp.cloudflare.com/mcp",
    "cloudflare-bindings": "https://bindings.mcp.cloudflare.com/mcp",
    "cloudflare-builds": "https://builds.mcp.cloudflare.com/mcp",
    "cloudflare-observability": "https://observability.mcp.cloudflare.com/mcp",
}
remote_mcps = {
    **cloudflare_mcps,
    "linear": "https://mcp.linear.app/mcp",
}
mcp = data.get("mcp")
if not isinstance(mcp, dict):
    mcp = {}
for name, url in remote_mcps.items():
    existing = mcp.get(name)
    if isinstance(existing, dict) and existing.get("url") == url:
        continue
    mcp[name] = {"type": "remote", "url": url, "enabled": True}
data["mcp"] = mcp

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

setup_opencode() {
  copy_agents_md
  merge_opencode_json
}

install_rtk() {
  if have rtk; then
    log "RTK already installed, skipping"
  else
    log "Installing RTK"
    curl -fsSL "https://raw.githubusercontent.com/rtk-ai/rtk/$RTK_VERSION/install.sh" | sh || die "RTK install failed"
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
    have rtk || die "RTK install did not put rtk on PATH"
  fi

  log "Initializing RTK for OpenCode"
  rtk init -g --opencode || die "RTK OpenCode init failed"
  rtk gain || true
}

install_plannotator() {
  if have plannotator; then
    log "Plannotator already installed, updating"
    curl -fsSL https://plannotator.ai/install.sh | bash -s -- --extras --non-interactive || die "Plannotator update failed"
  else
    log "Installing Plannotator core and extras"
    curl -fsSL https://plannotator.ai/install.sh | bash -s -- --extras --non-interactive || die "Plannotator install failed"
    export PATH="$HOME/.local/bin:$PATH"
    have plannotator || die "Plannotator install did not put plannotator on PATH"
  fi

  log "Installing Plannotator extra skills"
  npx -y skills add backnotprop/plannotator/apps/skills/extra -g -a opencode -y --copy || die "Plannotator extras install failed"

  cleanup_plannotator_cross_harness_side_effects
}

cleanup_plannotator_cross_harness_side_effects() {
  log "Removing non-OpenCode Plannotator installer side effects"

  rm -rf \
    "$HOME/.claude/skills/plannotator-review" \
    "$HOME/.claude/skills/plannotator-annotate" \
    "$HOME/.claude/skills/plannotator-last"

  rm -f \
    "$HOME/.gemini/commands/plannotator-review.toml" \
    "$HOME/.gemini/commands/plannotator-annotate.toml" \
    "$HOME/.gemini/policies/plannotator.toml"

  python3 - <<'PY'
import json
from pathlib import Path

home = Path.home()

codex_hooks = home / ".codex" / "hooks.json"
removed_codex_plannotator_hook = False
if codex_hooks.exists() and "plannotator" in codex_hooks.read_text(encoding="utf-8"):
    codex_hooks.unlink()
    removed_codex_plannotator_hook = True

codex_config = home / ".codex" / "config.toml"
if removed_codex_plannotator_hook and codex_config.exists():
    lines = codex_config.read_text(encoding="utf-8").splitlines()
    lines = [line for line in lines if line.strip() != "hooks = true"]
    codex_config.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")

gemini_settings = home / ".gemini" / "settings.json"
if gemini_settings.exists():
    try:
        data = json.loads(gemini_settings.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        data = None

    if isinstance(data, dict):
        hooks = data.get("hooks")
        if isinstance(hooks, dict):
            before_tool = hooks.get("BeforeTool")
            if isinstance(before_tool, list):
                hooks["BeforeTool"] = [
                    item for item in before_tool
                    if "plannotator" not in json.dumps(item)
                ]
                if not hooks["BeforeTool"]:
                    hooks.pop("BeforeTool")
            if not hooks:
                data.pop("hooks", None)

        gemini_settings.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY
}

install_plugins() {
  log "Installing plugins"
  install_rtk
  install_plannotator
}

install_skill() {
  local source="$1"
  local name="$2"
  log "Installing/updating skill: $name"

  npx -y skills add "$source" -g -a opencode -s "$name" -y --copy || die "Failed to install skill: $name"
}

install_local_skill() {
  local src_dir="$1"
  local name="$2"
  local dst="$HOME/.agents/skills/$name"
  log "Installing local skill: $name"

  [[ -d "$src_dir" ]] || die "Local skill source not found: $src_dir"

  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src_dir" "$dst"
}


install_cloudflare_skills() {
  log "Installing/updating Cloudflare skills"
  npx -y skills add https://github.com/cloudflare/skills -g -a opencode -y --copy || die "Cloudflare skills install failed"
}

install_required_skills() {
  log "Installing/updating required skills"

  mkdir -p "$HOME/.agents/skills"

  install_local_skill "$DOTFILES_DIR/agents/skills/find-skills" "find-skills"
  install_local_skill "$DOTFILES_DIR/agents/skills/auto-pr-review" "auto-pr-review"

  install_skill "JuliusBrussee/caveman" "caveman"
  install_skill "mattpocock/skills@productivity/grill-me" "grill-me"
  install_skill "mattpocock/skills@engineering/grill-with-docs" "grill-with-docs"
  install_skill "mattpocock/skills@productivity/handoff" "handoff"
  install_skill "mattpocock/skills@engineering/setup-matt-pocock-skills" "setup-matt-pocock-skills"
  install_skill "mattpocock/skills@engineering/tdd" "tdd"
  install_skill "mattpocock/skills@productivity/teach" "teach"
  install_skill "mattpocock/skills@engineering/to-tickets" "to-tickets"
  install_skill "mattpocock/skills@engineering/triage" "triage"
  install_skill "mattpocock/skills@productivity/writing-for-agents" "writing-for-agents"
  install_skill "shadcn/improve" "improve"
  install_skill "boristane/agent-skills" "logging-best-practices"

  install_cloudflare_skills
}

main() {
  log "Starting OpenCode agent stack setup"

  check_prerequisites
  install_opencode
  setup_opencode
  install_plugins
  install_required_skills

  log "Setup complete. Run ./agents/test.sh to verify."
}

main "$@"
