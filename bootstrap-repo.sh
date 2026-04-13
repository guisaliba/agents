#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${1:-$(pwd)}"

mkdir -p "$REPO_ROOT/.codex"

cat > "$REPO_ROOT/.codex/hooks.json" <<'EOF'
{
  "hooks": {
    "SessionStart": [
      {
        "type": "command",
        "command": "echo 'CAVEMAN MODE ACTIVE. Rules: Drop articles/filler/pleasantries/hedging. Fragments OK. Short synonyms. Pattern: [thing] [action] [reason]. [next step]. Code/commits/security: write normal. User says stop caveman or normal mode to deactivate.'"
      }
    ]
  }
}
EOF

if [ ! -f "$REPO_ROOT/AGENTS.md" ]; then
  cat > "$REPO_ROOT/AGENTS.md" <<'EOF'
# Project AGENTS.md

Add only project-specific instructions here.
Do not repeat global defaults that already live in ~/.codex/AGENTS.md and ~/.claude/CLAUDE.md or Cursor global rules.
EOF
fi

echo "Bootstrapped repo:"
echo "  $REPO_ROOT/.codex/hooks.json"
echo "  $REPO_ROOT/AGENTS.md"