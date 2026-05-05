
# Agents

This folder contains shared coding-agent configuration.

## Files

* `AGENTS.md`: canonical global instructions used by Codex, OpenCode, and Pi.
* `apply-agent-stack.sh`: applies the managed agent stack to the current machine.
* `codex/README.md`: Codex-specific notes.
* `opencode/README.md`: OpenCode-specific notes.
* `pi/README.md`: Pi-specific notes.
* `skills/README.md`: shared skills notes.

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
