#!/bin/bash
set -euo pipefail

BASE="$HOME/dotfiles/agents/AGENTS.base.md"
CLAUDE_OVERLAY="$HOME/dotfiles/agents/claude.overlay.md"
CODEX_OVERLAY="$HOME/dotfiles/agents/codex.overlay.md"
CURSOR_OVERLAY="$HOME/dotfiles/agents/cursor.overlay.md"
OPENCODE_OVERLAY="$HOME/dotfiles/agents/opencode.overlay.md"

mkdir -p "$HOME/.claude" \
         "$HOME/.codex" \
         "$HOME/.cursor/rules" \
         "$HOME/.config/opencode"

# Break any pre-existing symlinks/files at output paths so the `>` redirects
# below cannot follow a stale symlink and write to its target.
rm -f "$HOME/.claude/CLAUDE.md" \
      "$HOME/.codex/AGENTS.md" \
      "$HOME/.config/opencode/AGENTS.md" \
      "$HOME/.cursor/rules/00-global.mdc" \
      "$HOME/.cursor/rules/01-caveman.mdc"

# Merge base + overlay with a guaranteed newline between them.
# AGENTS.base.md has no trailing newline, so `cat base overlay` would glue the
# last line of base onto the first line of overlay.
merge() {
    local out="$1"; local base="$2"; local overlay="$3"
    { cat "$base"; echo; cat "$overlay"; } > "$out"
}

merge "$HOME/.claude/CLAUDE.md"           "$BASE" "$CLAUDE_OVERLAY"
merge "$HOME/.codex/AGENTS.md"            "$BASE" "$CODEX_OVERLAY"
merge "$HOME/.config/opencode/AGENTS.md"  "$BASE" "$OPENCODE_OVERLAY"

# Cursor global rule: frontmatter + merged base/overlay.
{
    cat <<'EOF'
---
description: "Global personal agent rules"
alwaysApply: true
---
EOF
    cat "$BASE"; echo; cat "$CURSOR_OVERLAY"
} > "$HOME/.cursor/rules/00-global.mdc"

# Cursor always-on Caveman rule.
cat > "$HOME/.cursor/rules/01-caveman.mdc" <<'EOF'
---
description: "Caveman mode - compressed communication"
alwaysApply: true
---

Terse like caveman. Technical substance exact. Only fluff die.
Drop: articles, filler (just/really/basically), pleasantries, hedging.
Fragments OK. Short synonyms. Code unchanged.
Pattern: [thing] [action] [reason]. [next step].
ACTIVE EVERY RESPONSE. No revert after many turns. No filler drift.
Code/commits/PRs: normal. Off: "stop caveman" / "normal mode".
EOF

echo "Synced:"
echo "  $HOME/.claude/CLAUDE.md"
echo "  $HOME/.codex/AGENTS.md"
echo "  $HOME/.config/opencode/AGENTS.md"
echo "  $HOME/.cursor/rules/00-global.mdc"
echo "  $HOME/.cursor/rules/01-caveman.mdc"
