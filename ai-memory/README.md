# ai-memory

Each host runs its own ai-memory service and keeps its own store. The service
listens on loopback at `127.0.0.1:49374`, which is also the default URL of the
ai-memory CLI. There is no remote mode: a host never uses another host's
service.

## Version

`apply.sh` pins ai-memory 3.3.1. Linux installs it from the AUR package
`ai-memory-bin`; macOS installs the checksum-verified release archive.

ai-memory 3.0 changed one default. `ai-memory init` on a **new** data
directory creates a root bearer token at `<data_dir>/auth-tokens/default` and
turns authentication on. The hooks and the MCP registration read that token
file, so no token goes into a harness configuration or the environment. An
**existing** 2.x data directory keeps its unauthenticated loopback service after
the upgrade. See the upstream
[3.0 upgrade notes](https://github.com/akitaonrails/ai-memory/blob/v3.3.1/docs/upgrading-to-3.0.md).
Take `ai-memory backup --to ~/ai-memory-pre-3.0.tar.gz` before the first apply
on a host that runs 2.x.

## Ownership

The service uses:

```text
~/.local/share/ai-memory
~/.config/ai-memory/config.toml
~/.config/ai-memory/env
~/.config/systemd/user/ai-memory.service
```

On macOS, apply installs the pinned native release under
`~/.local/opt/ai-memory/`, links it from `~/.local/bin/ai-memory`, and generates:

```text
~/.config/ai-memory/com.github.akitaonrails.ai-memory.plist
~/Library/Logs/ai-memory/
```

The generated plist has mode `0600` and contains no credentials. Install it as
the root-owned system service with:

```sh
launchctl bootout "gui/$(id -u)/com.github.akitaonrails.ai-memory" 2>/dev/null || true
sudo launchctl bootout system/com.github.akitaonrails.ai-memory 2>/dev/null || true
sudo install -o root -g wheel -m 0644 \
  "$HOME/.config/ai-memory/com.github.akitaonrails.ai-memory.plist" \
  /Library/LaunchDaemons/com.github.akitaonrails.ai-memory.plist
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/com.github.akitaonrails.ai-memory.plist
sudo launchctl kickstart -k system/com.github.akitaonrails.ai-memory
```

The LaunchDaemon starts at boot without a GUI login, runs as the user that
generated the plist, and loads `~/.config/ai-memory/env` before it starts the
service. Rerun the privileged sequence after an ai-memory binary, plist, or
environment change. After the daemon is active, apply removes the retired
LaunchAgent from `~/Library/LaunchAgents/`. Linux continues to use the systemd
user service.

The ai-memory binary owns the generated Claude Code hooks in
`~/.claude/settings.json`, the MCP registration in `~/.claude.json`, the routing
instructions in `~/.claude/rules/ai-memory.md`, and five ai-memory skills in
`~/.claude/skills/`. Do not edit generated files by hand. The pstack worker
profile (`~/.claude-worker`) never receives these hooks, so worker runs do not
write into the coordinator's workstream.

## LLM

You own `~/.config/ai-memory/env`. `apply.sh` creates it empty with mode `0600`
when it is absent, and never rewrites it. The service loads it through the
`EnvironmentFile=` line of its unit. To turn on the LLM jobs, write three lines:

```sh
AI_MEMORY_LLM_PROVIDER=opencode
AI_MEMORY_LLM_MODEL=deepseek-v4.1-flash
OPENCODE_API_KEY=sk-...
```

The `opencode` provider uses the OpenCode Go catalogue by default and reads its
key from `OPENCODE_API_KEY`. The same key feeds the pstack workers through
`bin/claude-worker-key` while `claude/worker/provider.env` names OpenCode Go as
the worker provider. After a change, restart the service with
`systemctl --user restart ai-memory` on Linux.

On every run, `apply.sh` reports the LLM state (`enabled`, or the names that are
not set) and warns about names that earlier versions wrote and that nothing
reads now: `AGENTS_AI_MEMORY_LLM_ENABLED`, `AGENTS_AI_MEMORY_REMOTE_MODE`,
`AI_MEMORY_SERVER_URL`, `DOTFILES_AI_MEMORY_LLM_ENABLED`,
`DOTFILES_AI_MEMORY_LLM_PROFILE`, and `DOTFILES_OPENCODE_SUBAGENT_PROFILE`.
Remove them by hand. Login shells do not load this file, so the key is not
exported to shell processes.

Captured content can be sent to the selected provider during explicit
consolidation, review, or reranking. Keep credentials, memory data, and the
ai-memory token pepper outside Git.

## Verify

```sh
ai-memory status --json
claude mcp list
```

On macOS, also verify the system service:

```sh
sudo launchctl print system/com.github.akitaonrails.ai-memory
```

## macOS Rollback

Remove the system service with:

```sh
sudo launchctl bootout system/com.github.akitaonrails.ai-memory 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.github.akitaonrails.ai-memory.plist
```

The command does not remove user data, configuration, credentials, or logs.

The managed workstream entry point is documented in
[`../shell/README.md`](../shell/README.md).
