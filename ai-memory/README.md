# ai-memory

`apply.sh` manages ai-memory as a native service and connects it to OpenCode
through the loopback MCP endpoint:

```text
http://127.0.0.1:49374/mcp
```

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
five ai-memory skills. Do not edit generated files by hand. The service LLM
is independent of the OpenCode session model.

The default profile is `opencode-go-muse`, which uses
`opencode-go/muse-spark-1.3-contributor`. The alternative profile is
`opencode-go-deepseek`. Both profiles stay in zero-LLM mode until
`OPENCODE_API_KEY` is present in the environment file.

Set `DOTFILES_AI_MEMORY_LLM_PROFILE` in `~/.config/ai-memory/env` to select
a profile. Apply preserves an explicit valid selection; remove the assignment
to use the default.

## Boundary

This setup uses unauthenticated loopback access. Apply rejects bearer-token
settings in the environment, service configuration, and `config.toml`.
Do not expose this endpoint beyond the local machine without designing
matching authentication and client wiring.

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
