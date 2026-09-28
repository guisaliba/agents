# ai-memory

The server owns the primary ai-memory store. It remains bound to loopback and is
published to the tailnet by Tailscale Serve with bearer authentication.

The published origin is a per-deployment value. It is never written into this
repository. Read it from the environment file on the host that serves it:

```sh
grep '^AI_MEMORY_SERVER_URL=' ~/.config/ai-memory/env
```

It has the shape `https://<server-host>:<port>`, and the MCP endpoint is that
origin plus `/mcp`. A server host leaves the variable unset and answers on
`http://127.0.0.1:49374`.

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

The ai-memory binary owns the generated OpenCode plugin, instructions, and
five ai-memory skills. Do not edit generated files by hand.

`DOTFILES_AI_MEMORY_LLM_PROFILE` is the single profile for the whole stack. It
sets the service LLM provider and model **and** the `general`, `explore` and
`title` OpenCode agents, so the two can no longer drift apart. Set it on the
**server** host only. A client runs no ai-memory service, and its sessions
execute on the server, so the server owns the value and the client deliberately
carries no copy. See [../opencode/README.md](../opencode/README.md) for the
full ownership rule and the change procedure.

The default profile is `opencode-go-deepseek-v4.1-flash`, which uses
`opencode-go/deepseek-v4.1-flash`. The alternative profile is
`opencode-go-muse-spark-1.3-contributor`, which uses
`opencode-go/muse-spark-1.3-contributor`. Both profiles stay in zero-LLM mode
until `OPENCODE_API_KEY` is present in the environment file.

Set `DOTFILES_AI_MEMORY_LLM_PROFILE` in `~/.config/ai-memory/env` to select
a profile. Apply preserves an explicit valid selection; remove the assignment
to use the default.

Set `DOTFILES_AI_MEMORY_LLM_ENABLED=false` in the same file to pause LLM jobs
without removing `OPENCODE_API_KEY`. After usage is restored, remove that
assignment, run `source ./apply.sh && configure_ai_memory_env_file`, and
restart the service with `systemctl --user restart ai-memory` on Linux.
Subagent selection is independent; see
[`../opencode/README.md`](../opencode/README.md).

## Boundary

The server backend remains on `127.0.0.1:49374`. Remote clients set
`AI_MEMORY_SERVER_URL` to the Tailscale HTTPS origin and keep the bearer token
in `~/.config/ai-memory/client-token`, mode `0600`. Apply stops the Linux local
service while a remote URL is active. The local data directory is retained as
an emergency fallback; automatic bidirectional store merge is out of scope.

Captured content can be sent to the selected provider during explicit
consolidation, review, or reranking. Keep credentials, memory data, and the
ai-memory token pepper outside Git.

## Verify

```sh
ai-memory status --json
opencode mcp list
opencode mcp debug ai-memory
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
