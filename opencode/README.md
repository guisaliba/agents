# OpenCode

`apply.sh` is the deployment source of truth for the global OpenCode V2 runtime.
It preserves unrelated valid configuration and fails without overwriting an
invalid JSON file or an invalid managed structure.

## Routing

```text
Primary, fixed by apply.sh:
  build -> openai/gpt-6-sol
  plan  -> openai/gpt-6-sol

Everything else, from one profile:
  general -> <profile>
  explore -> <profile>
  title   -> <profile>

  opencode-go-deepseek-v4.1-flash          -> opencode-go/deepseek-v4.1-flash
  opencode-go-muse-spark-1.3-contributor   -> opencode-go/muse-spark-1.3-contributor
```

## One Profile, and Who Owns It

`DOTFILES_AI_MEMORY_LLM_PROFILE` in `~/.config/ai-memory/env` is the **single**
selector. It decides, in one move:

- the ai-memory LLM provider and model
- the `general`, `explore` and `title` OpenCode agents
- nothing else. The primary `build` and `plan` models are fixed.

Set it **on the server host**. A client host must not set it.

```sh
# on the server, in ~/.config/ai-memory/env
DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-deepseek-v4.1-flash
```

Then run `./apply.sh` and restart the ai-memory service, because the running
service does not re-read the file on its own. `apply.sh` warns when the file and
the running process disagree.

### Why a client must not set it

A managed workstream is created by an `ai-memory run` process, and that process
runs wherever the command was typed. On a client, `opencode` forwards over SSH,
so the session executes on the **server**, and the server's `opencode.json` and
environment file decide the model. A profile on the client would be a copy that
governs nothing, and a stale copy is worse than none because it looks
authoritative. That is exactly how `agents.title` ended up holding a model id
no profile has ever produced.

So on a client, `apply.sh` writes **no** agent model and removes any model
already there, then tells you where the real value lives.

### Changing it

Change it on the server only:

```sh
# 1. edit DOTFILES_AI_MEMORY_LLM_PROFILE on the server
# 2. re-apply
./apply.sh
# 3. restart the service, or apply.sh warns that it is stale
sudo launchctl kickstart -k system/com.github.akitaonrails.ai-memory
```

All four values move together. There is no separate subagent selector any more.
`DOTFILES_OPENCODE_SUBAGENT_PROFILE` was removed for exactly that reason: three
selectors drifted apart, and the drift was silent.

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

On the server host, set `OPENCODE_SERVER_ENABLED=true` and put a non-empty
`OPENCODE_SERVER_PASSWORD` in `~/.config/opencode/server.env`. Apply installs a
root-owned LaunchDaemon that runs as the normal user and publishes its loopback
endpoint with Tailscale Serve. No GUI login is required after macOS boots.

The published origin is a per-deployment value and is never written into this
repository. It has the shape `https://<server-host>`, and a browser or a phone on
the tailnet uses it to reach the web UI and the API. A client reads it from
`OPENCODE_SERVER_URL` in its own `~/.config/opencode/server.env`.

The shell wrapper does not use the server. `opencode` always starts a local
ai-memory workstream, so a session never leaves the machine where you typed the
command. To work on the server, run `opencode` on the server.

See [V2-MIGRATION.md](V2-MIGRATION.md) for security, rollback, and acceptance.
