#!/usr/bin/env bash
set -Eeuo pipefail

repo="${OPEN_DESIGN_CHECKOUT:?OPEN_DESIGN_CHECKOUT is required}"
[[ -f "$repo/package.json" && -f "$repo/apps/daemon/bin/od.mjs" ]] || {
  printf 'OpenDesign checkout is missing: %s\n' "$repo" >&2
  exit 1
}

# tools-dev owns daemon lifecycle and assigns the port. Do not cache its URL.
status="$(cd "$repo" && pnpm tools-dev start daemon --json)"
url="$(python3 -c 'import json,sys; text=sys.stdin.read(); start=text.find("{"); data=json.loads(text[start:]); print(data["daemon"]["status"]["url"])' <<<"$status")"
[[ "$url" == http://127.0.0.1:* ]] || {
  printf 'OpenDesign daemon did not report a loopback URL\n' >&2
  exit 1
}
exec node "$repo/apps/daemon/bin/od.mjs" mcp --daemon-url "$url"
