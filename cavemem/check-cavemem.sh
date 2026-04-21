#!/usr/bin/env bash
set -euo pipefail

echo "== cavemem status =="
cavemem status || true

echo
echo "== cavemem doctor =="
cavemem doctor || true

echo
echo "== settings path =="
ls -la ~/.cavemem/settings.json || true

echo
echo "== data dir =="
ls -la ~/.cavemem || true