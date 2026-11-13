#!/bin/bash
# Setup script for a claude.ai cloud environment (Claude Code cloud sessions).
#
# Paste this file into the environment's "Setup script" field at claude.ai/code
# (environment selector > settings icon > Setup script). It runs as root on
# Ubuntu 24.04 before Claude Code starts, and its result is cached as a
# filesystem snapshot for about seven days, so it runs again only when you
# edit it, change the allowed network hosts, or the snapshot expires.
#
# The environment's variables are not set while this script runs, so every
# value it needs is set here. The OpenCode Go key is not needed here: store it
# as a network secret (see cloud/README.md).
set -euo pipefail

AGENTS_REPO="${AGENTS_REPO:-https://github.com/guisaliba/agents.git}"
AGENTS_REF="${AGENTS_REF:-main}"
AGENTS_DIR="${AGENTS_DIR:-/opt/agents}"

if ! command -v bwrap >/dev/null 2>&1 || ! command -v socat >/dev/null 2>&1; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq bubblewrap socat
fi

rm -rf -- "$AGENTS_DIR"
git clone --quiet --depth 1 --branch "$AGENTS_REF" "$AGENTS_REPO" "$AGENTS_DIR"
"$AGENTS_DIR/apply.sh" --cloud
