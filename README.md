# Agents

This folder contains OpenCode agent setup configuration.

## Files

- `AGENTS.md`: canonical global instructions used by OpenCode.
- `apply.sh`: installs and configures OpenCode, model routing, RTK, Plannotator, required skills, and the remote MCP servers (Cloudflare, Linear).
- `test.sh`: deterministic local checks for harness wiring.
- `opencode/README.md`: OpenCode-specific notes.
- `skills/README.md`: shared skills notes.

## Runtime Wiring

### OpenCode Model Routing

The global routing policy is:

```text
Primary:
  build -> GPT-5.6 Sol (openai/gpt-5.6-sol)
  plan  -> GPT-5.6 Sol (openai/gpt-5.6-sol)

Subagents:
  general -> DeepSeek V4 Flash (opencode-go/deepseek-v4-flash)
  explore -> DeepSeek V4 Flash (opencode-go/deepseek-v4-flash)
  scout   -> DeepSeek V4 Flash when OpenCode exposes native Scout
```

`general` keeps its normal built-in write, command, implementation, refactoring, debugging, and test capabilities. No custom agent or extra permission restriction is part of this policy. When a subagent changes the workspace, the primary agent must inspect the changes and run applicable verification before final acceptance. The complete rule is in `agents/AGENTS.md`.

`agents/apply.sh` merges the managed routing fields into `~/.config/opencode/opencode.json`. The global model selects Sol for `build`, and a direct agent override pins `plan` to Sol. The merge preserves unrelated root fields, agent entries, agent-specific fields, plugins, MCP servers, permissions, providers, and commands. If an existing runtime file has invalid JSON, a non-object root, or an invalid managed agent object, apply stops without overwriting the file.

Scout availability currently differs between OpenCode documentation and released/runtime implementations. Apply checks a clean OpenCode agent list. If OpenCode exposes native `scout (subagent)`, apply pins it to DeepSeek. If it does not, apply removes only this repository's prior Scout model override and does not create a custom or unrestricted fallback. `agents/test.sh` verifies the same boundary, so another supported device reports its effective Scout capability.

The script copies the complete canonical `agents/AGENTS.md` to `~/.config/opencode/AGENTS.md`. The source and deployed file must match exactly after apply.

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

Prerequisites are `curl`, `git`, `npm`, `npx`, and `python3`. On a new machine, authenticate the providers that supply `openai/gpt-5.6-sol` and `opencode-go/deepseek-v4-flash` with `opencode auth login` before use. Model policy is stored in Git. Provider API keys, OAuth tokens, and session credentials are not.

The script installs OpenCode if missing, copies `AGENTS.md` to `~/.config/opencode/AGENTS.md`, merges the global routing and integrations into `~/.config/opencode/opencode.json`, configures RTK for OpenCode, installs Plannotator core and extras, and installs/updates required skills. Upstream skills are installed live and tracked local skills are copied on every run. The Cloudflare skills bundle (`https://github.com/cloudflare/skills`) is installed as a group without `-s` so every upstream skill is pulled in. The Cloudflare remote MCP servers (`cloudflare-api`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability`) and the Linear remote MCP server (`linear`) are merged into the `mcp` block of `~/.config/opencode/opencode.json`; authenticate with `opencode mcp auth <name>`.

## Policy

Global OpenCode configuration is the default source of user-wide model and agent policy. Use `~/.config/opencode/opencode.json` for normal work. Add a project-level `opencode.json` only when that project has an explicit technical requirement for different settings. OpenCode's normal project-over-global precedence remains available for that exception.

Do not vendor upstream skill or plugin payloads in this repo.

Default rule: install live, do not track copies.

Exceptions: `find-skills` and `auto-pr-review` are local tracked skills under `agents/skills/`. `agents/apply.sh` copies them to `~/.agents/skills/` on every setup run.
