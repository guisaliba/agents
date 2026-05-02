#!/bin/bash
set -euo pipefail

BASE="$HOME/dotfiles/agents/AGENTS.base.md"
CODEX_OVERLAY="$HOME/dotfiles/agents/codex.overlay.md"
OPENCODE_OVERLAY="$HOME/dotfiles/agents/opencode.overlay.md"

mkdir -p "$HOME/.codex" \
         "$HOME/.config/opencode"

# Break any pre-existing symlinks/files at output paths so the `>` redirects
# below cannot follow a stale symlink and write to its target.
rm -f "$HOME/.codex/AGENTS.md" \
      "$HOME/.config/opencode/AGENTS.md" \

# Merge base + overlay with a guaranteed newline between them.
# AGENTS.base.md has no trailing newline, so `cat base overlay` would glue the
# last line of base onto the first line of overlay.
merge() {
    local out="$1"; local base="$2"; local overlay="$3"
    { cat "$base"; echo; cat "$overlay"; } > "$out"
}

merge "$HOME/.codex/AGENTS.md"            "$BASE" "$CODEX_OVERLAY"
merge "$HOME/.config/opencode/AGENTS.md"  "$BASE" "$OPENCODE_OVERLAY"

echo "Synced:"
echo "  $HOME/.codex/AGENTS.md"
echo "  $HOME/.config/opencode/AGENTS.md"