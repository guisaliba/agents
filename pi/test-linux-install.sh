#!/usr/bin/env bash
# Real Debian provisioning, without host credentials, memory data, or services.
set -Eeuo pipefail
REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
IMAGE=debian@sha256:7c7b2c966bc9ee8cedfeef67e0e279108992c77681fa595db4a9d65c06ccc587
exec docker run --rm --mount "type=bind,source=$REPO,target=/source,readonly" "$IMAGE" bash -c '
  set -Eeuo pipefail
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq curl git python3 chromium librsvg2-bin imagemagick xz-utils ca-certificates >/dev/null
  useradd --create-home --shell /bin/bash pi-test
  su - pi-test -c "/source/install.sh --no-service"
  su - pi-test -c "/source/install.sh --no-service"
  su - pi-test -c "env PATH=/home/pi-test/.local/share/pi-port/runtime/node/bin:/usr/bin:/bin /home/pi-test/.local/share/pi-port/packages/runtime/node_modules/.bin/pi --version"
  su - pi-test -c '\''
    set -eu
    export PATH="$HOME/.local/share/pi-port/runtime/node/bin:$HOME/.local/share/pi-port/runtime/rtk:/usr/bin:/bin"
    root="$HOME/.local/share/pi-port"
    /source/bin/pi-port-memory > "$HOME/memory-test.log" 2>&1 &
    pid=$!
    trap "kill $pid; wait $pid || true" EXIT
    python3 -B /source/lib/pi_port.py health "$root"
    python3 -B /source/pi/verify-resources.py --agent-dir "$root/agent" --memory-binary "$root/runtime/ai-memory/ai-memory" --memory-endpoint http://127.0.0.1:49375 --pi-binary "$root/packages/runtime/node_modules/.bin/pi" --subagents --ysk-model openai/gpt-6-luna --output "$HOME/resources.json"
    python3 -B /source/pi/verify-handoff.py --root "$root" --output "$HOME/handoff.json"
    python3 -B -c "import json,pathlib; print(json.dumps({name:json.loads((pathlib.Path.home()/(name+\".json\")).read_text()) for name in (\"resources\",\"handoff\")},indent=2))"
  '\''
  printf "PASS: Debian 12 provisioning, repeat install, resource discovery, and automatic handoff; no host credentials or store mounted.\n"
'
