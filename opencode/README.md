# OpenCode

`apply.sh` is the deployment source of truth for the global OpenCode runtime.
It preserves unrelated valid configuration and fails without overwriting an
invalid JSON file or an invalid managed structure.

## Routing

```text
Primary:
  build -> openai/gpt-5.6-sol
  plan  -> openai/gpt-5.6-sol

Subagents by `DOTFILES_AI_MEMORY_LLM_PROFILE`:
  opencode-go-deepseek-v4.1-flash (default) -> opencode-go/deepseek-v4.1-flash
  opencode-go-muse-spark-1.3-contributor    -> opencode-go/muse-spark-1.3-contributor
```

## Managed Paths

```text
~/.config/opencode/AGENTS.md
~/.config/opencode/opencode.json
~/.config/opencode/tui.json
~/.config/opencode/tui.jsonc
~/.config/opencode/themes/
~/.config/opencode/commands/
~/.agents/skills/
```

The tracked `AGENTS.md` is copied byte-for-byte to the global instruction
path. Global model, agent, plugin, MCP, and instruction entries are merged by
`apply.sh`. The detailed policy is in [`../AGENTS.md`](../AGENTS.md).

## Theme

The TUI theme key belongs in `tui.json`.
Tracked themes under `opencode/themes/` are copied to the global theme path.
The pinned asset provenance is recorded by the tracked theme file history.
Herdr owns only its plugin entry in `tui.jsonc`; Learn and the theme stay in
`tui.json`. OpenCode loads both files.

## Integrations

- [Plugins](../plugins/README.md) documents Learn, Herdr, Plannotator, and RTK.
- [Herdr](../herdr/README.md) documents host sessions and managed launches.
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
