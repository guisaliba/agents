#!/usr/bin/env bash
set -euo pipefail

if ! command -v cavemem >/dev/null 2>&1; then
  echo "Installing cavemem..."
  sudo npm install -g cavemem
fi

echo "Installing cavemem wiring..."
cavemem install                 # Claude Code
cavemem install --ide cursor
cavemem install --ide codex
cavemem install --ide opencode

echo
echo "Status:"
cavemem status

echo
echo "Doctor:"
cavemem doctor