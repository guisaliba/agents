# OpenCode

`apply.sh` is the deployment source of truth for the global OpenCode V2 runtime.
It preserves unrelated valid configuration and fails without overwriting an
invalid JSON file or an invalid managed structure.

## Routing

```text
Primary:
  build -> openai/gpt-6-sol
  plan  -> openai/gpt-6-sol

Subagents by `DOTFILES_OPENCODE_SUBAGENT_PROFILE`:
  opencode-go-deepseek-v4.1-flash (default) -> opencode-go/deepseek-v4.1-flash
  opencode-go-muse-spark-1.3-contributor    -> opencode-go/muse-spark-1.3-contributor
  openai-gpt-6-luna                         -> openai/gpt-6-luna
```

Set `DOTFILES_OPENCODE_SUBAGENT_PROFILE` in `~/.config/ai-memory/env` to
select a subagent model. Without it, subagents follow the ai-memory profile
for backward compatibility. The OpenAI profile uses OpenCode authentication;
it does not change the separate ai-memory LLM provider.

## Managed Paths

```text
~/.config/opencode/AGENTS.md
~/.config/opencode/opencode.json
~/.config/opencode/cli.json
~/.config/opencode/themes/
~/.config/opencode/commands/
~/.agents/skills/
```

The tracked `AGENTS.md` is copied byte-for-byte to the global instruction
path. Global model, agent, plugin, MCP, and instruction entries are merged by
`apply.sh`. The detailed policy is in [`../AGENTS.md`](../AGENTS.md).

## Theme

The terminal theme belongs in `cli.json` at `theme.name`.
Tracked themes under `opencode/themes/` are copied to the global theme path.
The pinned asset provenance is recorded by the tracked theme file history.
Learn is disabled until its server and terminal plugins have a verified V2 port.

## Keybinds

Managed keybinds belong in `keybinds` in `cli.json`. `apply.sh` merges them and
preserves unrelated user keybinds.

```text
session.sidebar.toggle -> ctrl+b   Toggle the sidebar
session.background     -> false    Disabled to free ctrl+b
input.move.left        -> left     ctrl+b removed to free it
```

The sidebar command is `session.sidebar.toggle`. Current OpenCode defaults bind
`ctrl+b` to `session.background` and to `input.move.left`. The merge disables
`session.background` and reduces `input.move.left` to `left`, so `ctrl+b` has
one owner only. An invalid `keybinds` structure fails without overwriting the
file.

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

## Central Server

On the M4, set `OPENCODE_SERVER_ENABLED=true` and put a non-empty
`OPENCODE_SERVER_PASSWORD` in `~/.config/opencode/server.env`. Apply installs a
root-owned LaunchDaemon that runs as the normal user and publishes its loopback
endpoint with Tailscale Serve. No GUI login is required after macOS boots.
Tailscale Serve publishes it at
`https://aurealabs-mac-mini-m4.taildc6550.ts.net`, which a browser or a phone on
the tailnet uses to reach the web UI and the API.

The shell wrapper does not use the server. `opencode` always starts a local
ai-memory workstream, so a session never leaves the machine where you typed the
command. To work on the M4, run `opencode` on the M4.

See [V2-MIGRATION.md](V2-MIGRATION.md) for security, rollback, and acceptance.
