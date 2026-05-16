
# Agents

This folder contains shared coding-agent configuration.

## Files

* `AGENTS.md`: canonical global instructions used by Codex, OpenCode, and Pi.
* `apply-agent-stack.sh`: applies the managed agent stack to the current machine.
* `codex/README.md`: Codex-specific notes.
* `opencode/README.md`: OpenCode-specific notes.
* `pi/README.md`: Pi-specific notes.
* `skills/README.md`: shared skills notes.

## Runtime Wiring

### Caveman

Caveman ultra is enabled by default in the canonical global instructions. Harness-specific lifecycle wiring reinforces it where supported:

* Codex: `SessionStart` hook in `~/.codex/hooks.json`.
* OpenCode: native plugin in `~/.config/opencode/plugins/caveman/`.
* Pi: local extension in `~/.pi/agent/extensions/caveman-autostart/`.

The default mode is also set for caveman-native integrations:

```json
{ "defaultMode": "ultra" }
```

Live path: `~/.config/caveman/config.json`.

Useful commands:

```sh
/caveman ultra
/caveman full
stop caveman
```

### Cavemem

Cavemem is installed as a shared memory layer.

* Codex: MCP server registered in `~/.codex/config.json`.
* OpenCode: MCP server registered in `~/.opencode/config.json`.
* Pi: custom tools registered by `~/.pi/agent/extensions/cavemem-bridge/`.

The embedding worker is configured with `autoStart: true`. `cavemem status` may show the worker stopped before first use; it starts on demand from hooks, MCP use, or viewer/search activity.

Useful commands:

```sh
cavemem status
cavemem search "query"
cavemem viewer
```

### RTK

RTK is installed as the shell/tool-output compaction layer.

* Codex: `~/.codex/AGENTS.md` includes `~/.codex/RTK.md`.
* OpenCode: command rewrite plugin installed at `~/.config/opencode/plugins/rtk.ts`.
* Pi: command rewrite extension installed at `~/.pi/agent/extensions/rtk/`.

Useful commands:

```sh
rtk rewrite "git status --short"
rtk gain
rtk <command>
```

## Apply

From the repo root:

```sh
./agents/apply-agent-stack.sh
```

Or from this directory:

```sh
./apply-agent-stack.sh
```

By default the script applies local config only. Use `COMMIT=1` to commit generated repo changes and `COMMIT=1 PUSH=1` to push them.

## Policy

Do not maintain separate base and overlay Markdown files unless a harness genuinely needs different behavior.

Default rule: one source of truth, multiple placements.
