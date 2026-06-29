# Agents

This folder contains OpenCode agent setup configuration.

## Files

- `AGENTS.md`: canonical global instructions used by OpenCode.
- `apply.sh`: installs and configures OpenCode, RTK, Plannotator, and required skills.
- `test.sh`: deterministic local checks for harness wiring.
- `opencode/README.md`: OpenCode-specific notes.
- `skills/README.md`: shared skills notes.

## Runtime Wiring

### RTK

RTK is installed as the shell/tool-output compaction layer.

- OpenCode: command rewrite plugin installed at `~/.config/opencode/plugins/rtk.ts`.

Useful commands:

```sh
rtk rewrite "git status --short"
rtk gain
rtk <command>
```

### Plannotator

Plannotator is installed as the plan review and code review layer.

- Binary: installed automatically when missing via the official installer.
- OpenCode: plugin `@plannotator/opencode@latest` in `~/.config/opencode/opencode.json`. Commands at `~/.config/opencode/commands/plannotator-*`.
- Shared skills: `plannotator-compound`, `plannotator-setup-goal`, `plannotator-visual-explainer` at `~/.agents/skills/`.

Useful commands:

```sh
plannotator review [pr-url]
plannotator annotate <file|url|folder>
plannotator last
```

## Apply

From the repo root:

```sh
./agents/apply.sh
./agents/test.sh
```

The script installs OpenCode if missing, copies `AGENTS.md` to `~/.config/opencode/AGENTS.md`, merges `~/.config/opencode/opencode.json`, configures RTK for OpenCode, installs Plannotator core and extras, and installs/updates required skills. Skills are installed live from upstream sources every run.

## Policy

Do not vendor upstream skill or plugin payloads in this repo.

Default rule: install live, do not track copies.

Exception: `auto-pr-review` is a local-only skill tracked under `agents/skills/auto-pr-review/`. Install it manually if needed.