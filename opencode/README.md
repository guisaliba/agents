# OpenCode

`apply.sh` is the deployment source of truth for the global OpenCode runtime.
It preserves unrelated valid configuration and fails without overwriting an
invalid JSON file or an invalid managed structure.

## Routing

```text
Primary:
  build -> openai/gpt-5.6-sol
  plan  -> openai/gpt-5.6-sol

Subagents:
  general -> opencode-go/deepseek-v4-flash
  explore -> opencode-go/deepseek-v4-flash
  scout   -> opencode-go/deepseek-v4-flash when native Scout exists
```

Scout is configured only when OpenCode exposes the native `scout (subagent)`.
Apply does not create a custom Scout fallback.

## Managed Paths

```text
~/.config/opencode/AGENTS.md
~/.config/opencode/opencode.json
~/.config/opencode/tui.json
~/.config/opencode/themes/
~/.config/opencode/commands/
~/.agents/skills/
```

The tracked `AGENTS.md` is copied byte-for-byte to the global instruction
path. Global model, agent, plugin, MCP, and instruction entries are merged by
`apply.sh`. The detailed policy is in [`../AGENTS.md`](../AGENTS.md).

## Theme

The TUI theme key belongs in `tui.json` and is converged to `lucent-orng`.
Tracked themes under `opencode/themes/` are copied to the global theme path.
The pinned asset provenance is recorded by the tracked theme file history.

## Integrations

- [Plugins](../plugins/README.md) documents Learn, Plannotator, and RTK.
- [MCP servers](../mcps/README.md) documents GitHub, Linear, and Cloudflare.
- [ai-memory](../ai-memory/README.md) provides memory and workstreams.
- [Shell entry point](../shell/README.md) manages interactive sessions.
- [Skills](../skills/README.md) owns global skill installation.

## Verify

```sh
./test.sh --repo-only
opencode --version
opencode mcp list
```

Restart OpenCode after a configuration or theme change.
