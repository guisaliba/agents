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

### Plannotator

Plannotator is installed as the plan review and code review layer.

* Binary: installed automatically when missing via the official installer. Pin with `PLANNOTATOR_VERSION=vX.Y.Z`.
* Codex: `Stop` hook in `~/.codex/hooks.json` opens plan review UI. Command skills at `~/.codex/skills/plannotator-*`.
* OpenCode: plugin `@plannotator/opencode@latest` in `~/.config/opencode/opencode.json`. Commands at `~/.config/opencode/commands/plannotator-*`.
* Pi: package `npm:@plannotator/pi-extension` in `~/.pi/agent/settings.json`.
* Shared skills: `plannotator-compound`, `plannotator-setup-goal`, `plannotator-visual-explainer` at `~/.agents/skills/`.

Useful commands:

```sh
plannotator review [pr-url]
plannotator annotate <file|url|folder>
plannotator last
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
