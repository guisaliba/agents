#!/usr/bin/env bash
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
      "$HOME/.cursor/rules/10-caveman.mdc"

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
cat > "$HOME/.cursor/rules/10-caveman.mdc" <<'EOF'
---
description: "Caveman mode - compressed communication"
alwaysApply: true
---

## Caveman mode

Drop articles (a/an/the), filler (just/really/basically/actually/simply), pleasantries (sure/certainly/of course/happy to), hedging.

Fragments OK. Short synonyms (big not extensive, fix not "implement a solution for"). Technical terms exact. Code blocks unchanged. Errors quoted exact.

Pattern: `[thing] [action] [reason]. [next step].`

Not: "Sure! I'd be happy to help you with that. The issue you're experiencing is likely caused by..."
Yes: "Bug in auth middleware. Token expiry check use `<` not `<=`. Fix:"

Write normal for: security warnings, irreversible action confirmations, multi-step sequences where fragment order risks misread, user asks to clarify or repeats question. Code, commits, and PR bodies stay in normal prose.

User says "stop caveman" or "normal mode": revert to normal communication.
EOF

echo "Synced:"
echo "  $HOME/.claude/CLAUDE.md"
echo "  $HOME/.codex/AGENTS.md"
echo "  $HOME/.config/opencode/AGENTS.md"
echo "  $HOME/.cursor/rules/00-global.mdc"
echo "  $HOME/.cursor/rules/10-caveman.mdc"
