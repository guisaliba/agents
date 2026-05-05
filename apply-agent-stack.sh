#!/usr/bin/env bash
set -Eeuo pipefail

# apply-agent-stack.sh
#
# Usage:
#   ./agents/apply-agent-stack.sh
#
# Optional:
#   DOTFILES_DIR="$HOME/dotfiles" ./agents/apply-agent-stack.sh
#   RUN_AGENT_DOCS=1 ./agents/apply-agent-stack.sh
#   COMMIT=1 ./agents/apply-agent-stack.sh
#   COMMIT=1 PUSH=1 ./agents/apply-agent-stack.sh
#   COMMIT=1 CREATE_BRANCH=1 BRANCH=chore/agent-stack ./agents/apply-agent-stack.sh
#
# Defaults:
#   - uses this script's repo checkout as DOTFILES_DIR
#   - writes and applies managed agent configuration locally
#   - skips nested Pi review unless RUN_AGENT_DOCS=1
#   - does NOT commit unless COMMIT=1
#   - does NOT push unless COMMIT=1 PUSH=1

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CHEZMOI_SRC="${CHEZMOI_SRC:-$DOTFILES_DIR/chezmoi}"
BRANCH="${BRANCH:-chore/agent-stack-chezmoi}"
RUN_AGENT_DOCS="${RUN_AGENT_DOCS:-0}"
COMMIT="${COMMIT:-0}"
PUSH="${PUSH:-0}"
CREATE_BRANCH="${CREATE_BRANCH:-0}"
RTK_VERSION="${RTK_VERSION:-v0.38.0}"

log() {
  printf '\n==> %s\n' "$*"
}

warn() {
  printf '\nWARN: %s\n' "$*" >&2
}

die() {
  printf '\nERROR: %s\n' "$*" >&2
  exit 1
}

have() {
  command -v "$1" >/dev/null 2>&1
}

write_file() {
  local path="$1"
  mkdir -p "$(dirname "$path")"
  cat > "$path"
}

copy_dir_clean() {
  local src="$1"
  local dst="$2"
  rm -rf "$dst"
  mkdir -p "$(dirname "$dst")"
  cp -a "$src" "$dst"
}

copy_file_replace_symlink() {
  local src="$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  rm -f "$dst"
  cp "$src" "$dst"
}

json_update_pi_settings() {
  local settings="$HOME/.pi/agent/settings.json"
  mkdir -p "$(dirname "$settings")"

  python3 - "$settings" <<'PY'
import json
import os
import sys

path = sys.argv[1]
data = {}

if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        backup = path + ".bak"
        os.replace(path, backup)
        data = {}

def uniq(seq):
    out = []
    for item in seq:
        if item not in out:
            out.append(item)
    return out

data["skills"] = uniq(list(data.get("skills", [])) + [
    "~/.agents/skills",
    "~/.pi/agent/skills",
])
data["extensions"] = uniq(list(data.get("extensions", [])) + [
    "~/.pi/agent/extensions/rtk",
    "~/.pi/agent/extensions/cavemem-bridge",
])

with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
PY
}

require_repo() {
  [[ -d "$DOTFILES_DIR" ]] || die "DOTFILES_DIR does not exist: $DOTFILES_DIR"
  [[ -d "$DOTFILES_DIR/.git" ]] || die "DOTFILES_DIR is not a git repo: $DOTFILES_DIR"
}

setup_branch() {
  cd "$DOTFILES_DIR"

  if [[ "$COMMIT" != "1" || "$CREATE_BRANCH" != "1" ]]; then
    return
  fi

  if git rev-parse --verify "$BRANCH" >/dev/null 2>&1; then
    git switch "$BRANCH" || warn "Could not switch to existing branch $BRANCH. Continuing on current branch."
  else
    git switch -c "$BRANCH" || warn "Could not create branch $BRANCH. Continuing on current branch."
  fi
}

backup_path_if_present() {
  local path="$1"
  local backup="$2"

  if [[ -e "$path" || -L "$path" ]]; then
    mkdir -p "$backup/$(dirname "${path#$HOME/}")"
    cp -a "$path" "$backup/${path#$HOME/}"
  fi
}

backup_existing_targets() {
  local ts
  ts="$(date +%Y%m%d-%H%M%S)"
  local backup="$DOTFILES_DIR/.agent-stack-backup/$ts"

  mkdir -p "$backup"

  for p in \
    "$HOME/.codex/AGENTS.md" \
    "$HOME/.codex/config.toml" \
    "$HOME/.config/opencode/AGENTS.md" \
    "$HOME/.config/opencode/.gitignore" \
    "$HOME/.config/opencode/bun.lock" \
    "$HOME/.config/opencode/package.json" \
    "$HOME/.opencode/AGENTS.md" \
    "$HOME/.opencode/plugins/rtk.ts" \
    "$HOME/.pi/agent/AGENTS.md" \
    "$HOME/.pi/agent/settings.json"
  do
    backup_path_if_present "$p" "$backup"
  done

  log "Backed up existing agent targets to $backup"
}

remove_if_legacy_opencode_repo_link() {
  local path="$1"

  if [[ -L "$path" ]]; then
    local target
    target="$(readlink "$path")"
    if [[ "$target" == "$DOTFILES_DIR/opencode/"* || "$target" == "$DOTFILES_DIR/AGENTS.md" ]]; then
      rm -f "$path"
      log "Removed deprecated OpenCode symlink: $path -> $target"
    fi
  fi
}

cleanup_deprecated_targets() {
  log "Cleaning deprecated agent targets"

  rm -f "$HOME/.opencode/AGENTS.md" "$HOME/.opencode/plugins/rtk.ts"
  rmdir "$HOME/.opencode/plugins" 2>/dev/null || true

  remove_if_legacy_opencode_repo_link "$HOME/.config/opencode/.gitignore"
  remove_if_legacy_opencode_repo_link "$HOME/.config/opencode/bun.lock"
  remove_if_legacy_opencode_repo_link "$HOME/.config/opencode/package.json"

  find "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.pi/agent" -xtype l -print -delete 2>/dev/null || true
}

sync_canonical_agents_md() {
  log "Using canonical agents/AGENTS.md"

  local src="$DOTFILES_DIR/agents/AGENTS.md"
  [[ -f "$src" ]] || die "Missing canonical agent instructions: $src"

  mkdir -p "$CHEZMOI_SRC/.chezmoitemplates/agents"
  cp "$src" "$CHEZMOI_SRC/.chezmoitemplates/agents/AGENTS.md"
}

write_chezmoi_source() {
  log "Writing chezmoi source tree under $CHEZMOI_SRC"

  mkdir -p "$CHEZMOI_SRC/.chezmoitemplates/agents"
  cp "$DOTFILES_DIR/agents/AGENTS.md" "$CHEZMOI_SRC/.chezmoitemplates/agents/AGENTS.md"

  write_file "$CHEZMOI_SRC/dot_codex/AGENTS.md.tmpl" <<'EOF'
{{ include ".chezmoitemplates/agents/AGENTS.md" }}
EOF

  write_file "$CHEZMOI_SRC/dot_config/opencode/AGENTS.md.tmpl" <<'EOF'
{{ include ".chezmoitemplates/agents/AGENTS.md" }}
EOF

  write_file "$CHEZMOI_SRC/dot_pi/agent/AGENTS.md.tmpl" <<'EOF'
{{ include ".chezmoitemplates/agents/AGENTS.md" }}
EOF

  if [[ -f "$DOTFILES_DIR/agents/codex/config.toml" ]]; then
    mkdir -p "$CHEZMOI_SRC/dot_codex"
    cp "$DOTFILES_DIR/agents/codex/config.toml" "$CHEZMOI_SRC/dot_codex/config.toml"
  fi
}

materialize_agent_targets() {
  log "Materializing AGENTS.md into global harness locations"

  mkdir -p "$HOME/.codex" "$HOME/.config/opencode" "$HOME/.pi/agent"

  copy_file_replace_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.codex/AGENTS.md"
  copy_file_replace_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.config/opencode/AGENTS.md"
  copy_file_replace_symlink "$DOTFILES_DIR/agents/AGENTS.md" "$HOME/.pi/agent/AGENTS.md"

  if [[ -f "$DOTFILES_DIR/agents/codex/config.toml" ]]; then
    copy_file_replace_symlink "$DOTFILES_DIR/agents/codex/config.toml" "$HOME/.codex/config.toml"
  fi
}

install_chezmoi_if_missing() {
  if have chezmoi; then
    return
  fi

  log "Installing chezmoi into ~/.local/bin"
  mkdir -p "$HOME/.local/bin"
  sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"

  export PATH="$HOME/.local/bin:$PATH"

  have chezmoi || warn "chezmoi install did not put chezmoi on PATH"
}

apply_chezmoi_source() {
  if ! have chezmoi; then
    warn "chezmoi not available. Direct target files were already written."
    return
  fi

  log "Applying chezmoi source from $CHEZMOI_SRC"
  chezmoi apply --source "$CHEZMOI_SRC" --force --no-tty -v || warn "chezmoi apply failed. Direct target files were already written."
}

install_agent_skills() {
  log "Installing shared agent skills"

  have git || die "git is required"
  mkdir -p "$HOME/.agents/skills"
  mkdir -p "$CHEZMOI_SRC/dot_agents/skills"

  local tmp tmp_quoted
  tmp="$(mktemp -d)"
  printf -v tmp_quoted '%q' "$tmp"
  trap "rm -rf $tmp_quoted" EXIT

  git clone --depth 1 https://github.com/mattpocock/skills "$tmp/matt-skills"

  for skill in \
    "productivity/grill-me" \
    "engineering/grill-with-docs" \
    "engineering/tdd"
  do
    local name
    name="$(basename "$skill")"

    copy_dir_clean "$tmp/matt-skills/skills/$skill" "$HOME/.agents/skills/$name"
    copy_dir_clean "$tmp/matt-skills/skills/$skill" "$CHEZMOI_SRC/dot_agents/skills/$name"
  done

  if [[ -d "$CHEZMOI_SRC/dot_agents/skills/find-skills" ]]; then
    copy_dir_clean "$CHEZMOI_SRC/dot_agents/skills/find-skills" "$HOME/.agents/skills/find-skills"
  else
    warn "find-skills source not found under $CHEZMOI_SRC/dot_agents/skills"
  fi

  rm -rf "$tmp"
  trap - EXIT
}

install_external_tools() {
  log "Installing cavemem, caveman, and rtk integrations where supported"

  if have npm; then
    if have cavemem; then
      log "cavemem already available. Skipping global npm install."
    else
      mkdir -p "$HOME/.local"
      npm install -g --prefix "$HOME/.local" cavemem || warn "Failed to install cavemem globally"
      export PATH="$HOME/.local/bin:$PATH"
    fi
  else
    warn "npm not found. Skipping npm-based installs: cavemem and caveman skills installer."
  fi

  if have cavemem; then
    cavemem install --ide codex || warn "cavemem codex install failed"
    cavemem install --ide opencode || warn "cavemem opencode install failed"
    cavemem doctor || true
    cavemem status || true
  else
    warn "cavemem not found. Skipping cavemem IDE wiring."
  fi

  if have npm; then
    npx -y skills add JuliusBrussee/caveman -g -a codex -s caveman -y --copy || warn "caveman codex install failed"
    npx -y skills add JuliusBrussee/caveman -g -a opencode -s caveman -y --copy || warn "caveman opencode install failed"

    if [[ -d "$CHEZMOI_SRC/dot_agents/skills/find-skills" ]]; then
      npx -y skills add "$CHEZMOI_SRC/dot_agents/skills/find-skills" -g -a codex -s find-skills -y --copy || warn "find-skills codex install failed"
      npx -y skills add "$CHEZMOI_SRC/dot_agents/skills/find-skills" -g -a opencode -s find-skills -y --copy || warn "find-skills opencode install failed"
      npx -y skills add "$CHEZMOI_SRC/dot_agents/skills/find-skills" -g -a pi -s find-skills -y --copy || warn "find-skills pi install failed"
    fi

    if [[ -d "$HOME/.agents/skills/caveman" ]]; then
      copy_dir_clean "$HOME/.agents/skills/caveman" "$CHEZMOI_SRC/dot_agents/skills/caveman"
    else
      warn "caveman skill was not found under ~/.agents/skills after install"
    fi
  fi

  if ! have rtk; then
    curl -fsSL "https://raw.githubusercontent.com/rtk-ai/rtk/$RTK_VERSION/install.sh" | sh || warn "rtk install failed"
    export PATH="$HOME/.local/bin:$HOME/bin:$PATH"
  fi

  if have rtk; then
    rtk init -g --codex || warn "rtk codex init failed"
    rtk init -g --opencode || warn "rtk opencode init failed"

    if [[ -f "$HOME/.config/opencode/plugins/rtk.ts" ]]; then
      mkdir -p "$CHEZMOI_SRC/dot_config/opencode/plugins"
      cp "$HOME/.config/opencode/plugins/rtk.ts" "$CHEZMOI_SRC/dot_config/opencode/plugins/rtk.ts"
    fi

    rtk gain || true
  fi

  if have pi; then
    pi install git:github.com/v2nic/pi-caveman || warn "pi-caveman install failed"
  else
    warn "pi not found. Pi-specific extension files will still be written."
  fi
}

write_pi_rtk_extension() {
  log "Writing Pi RTK extension"

  local dst="$HOME/.pi/agent/extensions/rtk"
  local src="$CHEZMOI_SRC/dot_pi/agent/extensions/rtk"

  mkdir -p "$dst" "$src"

  for base in "$dst" "$src"; do
    write_file "$base/index.ts" <<'EOF'
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { isToolCallEventType } from "@mariozechner/pi-coding-agent";
import { execFile } from "node:child_process";
import { promisify } from "node:util";

const execFileAsync = promisify(execFile);

export default function (pi: ExtensionAPI) {
  pi.on("tool_call", async (event, ctx) => {
    if (!isToolCallEventType("bash", event)) return;

    const command = event.input.command;
    if (typeof command !== "string" || command.trim() === "") return;
    if (command.startsWith("rtk ")) return;
    if (command.includes("RTK_DISABLED=1")) return;

    try {
      const { stdout } = await execFileAsync("rtk", ["rewrite", command], {
        signal: ctx.signal,
      });

      const rewritten = stdout.trim();

      if (rewritten && rewritten !== command) {
        event.input.command = rewritten;
        ctx.ui.setStatus("rtk", "rtk");
      }
    } catch {
      return;
    }
  });
}
EOF
  done
}

write_pi_cavemem_bridge_extension() {
  log "Writing Pi cavemem MCP bridge extension"

  local source="$DOTFILES_DIR/agents/pi/extensions/cavemem-bridge"
  local dst="$HOME/.pi/agent/extensions/cavemem-bridge"
  local src="$CHEZMOI_SRC/dot_pi/agent/extensions/cavemem-bridge"

  [[ -d "$source" ]] || die "Missing Pi cavemem bridge extension source: $source"

  copy_dir_clean "$source" "$dst"
  copy_dir_clean "$source" "$src"

  if have npm; then
    (cd "$dst" && npm install --omit=dev) || warn "npm install failed for Pi cavemem bridge"
  else
    warn "npm not found. Pi cavemem bridge dependency install skipped."
  fi
}

write_pi_settings() {
  log "Updating Pi settings"
  json_update_pi_settings

  mkdir -p "$CHEZMOI_SRC/dot_pi/agent"
  cp "$HOME/.pi/agent/settings.json" "$CHEZMOI_SRC/dot_pi/agent/settings.json"
}

write_docs() {
  log "Validating repository documentation"

  local docs=(
    "$DOTFILES_DIR/README.md"
    "$DOTFILES_DIR/agents/README.md"
    "$DOTFILES_DIR/agents/codex/README.md"
    "$DOTFILES_DIR/agents/opencode/README.md"
    "$DOTFILES_DIR/agents/pi/README.md"
    "$DOTFILES_DIR/agents/skills/README.md"
  )

  local doc
  for doc in "${docs[@]}"; do
    [[ -f "$doc" ]] || warn "Missing documentation file: $doc"
  done
}

invoke_pi_for_docs_and_bridge_review() {
  if [[ "$RUN_AGENT_DOCS" != "1" ]]; then
    log "Skipping agent-driven documentation review"
    return
  fi

  if ! have pi; then
    warn "Pi not found. Skipping agent-driven documentation review."
    return
  fi

  log "Invoking Pi to review docs and Pi cavemem bridge"

  local prompt
  prompt="$(mktemp)"

  cat > "$prompt" <<'EOF'
You are working inside my dotfiles repo.

Task:
Review and update the documentation for the new global agent stack.

Scope:

* Root README.md
* agents/README.md
* agents/codex/README.md
* agents/opencode/README.md
* agents/pi/README.md
* agents/skills/README.md
* Pi extensions under agents/pi/extensions/ and chezmoi/dot_pi/agent/extensions/

Context:

* The repo now uses one canonical agents/AGENTS.md.
* The old base-plus-overlay merge model should be considered deprecated.
* Chezmoi source lives under ./chezmoi to avoid treating the whole repo root as chezmoi source.
* Codex target: ~/.codex/AGENTS.md
* OpenCode target: ~/.config/opencode/AGENTS.md
* Pi target: ~/.pi/agent/AGENTS.md
* Shared skills target: ~/.agents/skills
* Required skills: caveman, find-skills, grill-me, grill-with-docs, tdd.
* Required tools: caveman, cavemem, rtk.
* Cavemem exposes a stdio MCP server through `cavemem mcp`.
* Pi does not have documented native MCP client config in this setup, so the repo scaffolds a Pi extension bridge that registers custom Pi tools and forwards to cavemem MCP.
* Do not invent unsupported claims.
* Keep docs concise.
* Do not remove the deterministic documentation structure unless there is a clear reason.
* If the Pi cavemem bridge is wrong or fragile, fix it with the smallest coherent change.
* After editing, run the closest relevant checks available, at least TypeScript/package install checks for the extension if practical.
EOF

  (
    cd "$DOTFILES_DIR"
    pi -p "$(cat "$prompt")" || warn "Pi documentation/bridge review failed"
  )

  rm -f "$prompt"
}

git_commit_and_push() {
  cd "$DOTFILES_DIR"

  log "Git status"
  git status --short

  if [[ "$COMMIT" != "1" ]]; then
    log "Skipping commit. Re-run with COMMIT=1 to commit repository changes."
    return
  fi

  git add -A -- .

  if git diff --cached --quiet; then
    log "No git changes to commit"
    return
  fi

  git commit -m "chore(agent-stack): apply managed agent configuration" || warn "git commit failed"

  if [[ "$PUSH" == "1" ]]; then
    git push -u origin "$(git branch --show-current)" || warn "git push failed"
  else
    log "Skipping push. Re-run with COMMIT=1 PUSH=1 to push the branch."
  fi
}

main() {
  require_repo
  setup_branch
  backup_existing_targets
  cleanup_deprecated_targets

  sync_canonical_agents_md
  write_chezmoi_source
  materialize_agent_targets

  install_chezmoi_if_missing
  apply_chezmoi_source

  install_agent_skills
  install_external_tools

  write_pi_rtk_extension
  write_pi_cavemem_bridge_extension
  write_pi_settings

  write_docs
  invoke_pi_for_docs_and_bridge_review

  git_commit_and_push

  log "Done"
}

main "$@"
