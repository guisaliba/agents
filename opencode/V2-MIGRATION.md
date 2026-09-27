# OpenCode V2 Migration

## Inventory

- The source workstation had OpenCode V1 `1.18.30` through mise.
- The server host had OpenCode V1 `1.18.32` at `~/.opencode/bin/opencode`.
- The native V2 release used for this migration is `2.0.18`.
- The closed Orca pull request was not merged. Main and the current worktree contain no Orca files, port `6768`, PF anchors, pairing code, or Orca service definitions.
- The server host ai-memory store had 2 sessions and 8 observations. The promoted workstation store had 238 current pages, 271 sessions, and 48,991 observations at cutover.

## Migration Matrix

| V1 behavior | V2 replacement | Files | Verification | Status |
| --- | --- | --- | --- | --- |
| `agent` | `agents` | `apply.sh`, `test.sh` | Merge fixture and V2 runtime | Ready |
| `plugin` | `plugins` | `apply.sh`, `test.sh` | Plugin list | Ready |
| Flat `mcp` entries | `mcp.servers` with inverse `disabled` | `apply.sh`, `test.sh` | MCP list and fixture | Ready |
| `tui.json(c)` | Global `cli.json` | `apply.sh`, `test.sh` | Schema, theme, Ctrl+B | Ready |
| Local ai-memory | Authenticated server endpoint | `apply.sh`, `ai-memory/README.md` | MCP `tools/list` | Ready |
| Plannotator V1 tuple | V2 plugin object | `apply.sh` | `submit_plan` behavior | Ready upstream |
| Learn V1 server and TUI plugins | V2 server and CLI plugins | Learn repository | Full quiz and UI E2E | Blocked; disabled |
| RTK V1 hook | Released V2 `execute.before` hook | RTK upstream | Real V2 command rewrite | Blocked; disabled |
| Local TUI/server process | Server `opencode serve` for the web UI only | `apply.sh` | Web UI on a tailnet device | Ready; the remote TUI path is dropped |

## Server Service

OpenCode V2 `2.0.18` has one `serve` command that supplies the API and web UI. It does not have the older separate `web` command. A root-owned LaunchDaemon runs the process as the normal user:

```sh
opencode serve --hostname 127.0.0.1 --port 4096
```

Tailscale Serve publishes that loopback endpoint to the tailnet. The backend remains unavailable on LAN interfaces. `OPENCODE_SERVER_PASSWORD` is mandatory and is read from `~/.config/opencode/server.env`, mode `0600`.

The shell wrapper does not connect to that server. There is no client-to-server path translation, because a session is never relocated to another machine. `opencode` starts a local ai-memory workstream. A browser or a phone reaches the web UI over Tailscale Serve; that session is captured by the server plugin but has no workstream. To get a managed session on the server, run `opencode` on the server.

No GUI login is required. FileVault is a separate boot boundary: after an unexpected reboot, macOS, Tailscale, and all LaunchDaemons remain unavailable until the disk is unlocked at the preboot screen. A planned authenticated restart can use `fdesetup authrestart`; unattended recovery after power loss requires disabling FileVault or using remote preboot keyboard/video hardware.

## Security Review

- OpenCode and ai-memory bind only to loopback.
- Tailscale Serve terminates HTTPS and applies tailnet ACLs.
- OpenCode also requires HTTP Basic Auth.
- ai-memory requires a bearer token and uses a separate HTTPS Serve port.
- No public Funnel, public CORS origin, PF rule, or `0.0.0.0` listener is required.
- Provider credentials, MCP credentials, repositories, sessions, and worktrees stay on the server for remote sessions.
- Client token files and server environment files use mode `0600`.

## Rollback

`apply.sh` creates `~/.local/share/opencode-v1-backup` once before it converts V1 state. It contains the prior binary, `opencode.json(c)`, `tui.json(c)`, generated plugins, credentials when present, and a consistent SQLite backup when `sqlite3` is available.

1. Stop the V2 LaunchDaemon and disable Tailscale Serve.
2. Restore the backed-up V1 binary to its original package-manager path or reinstall the recorded version with that package manager.
3. Restore the backed-up V1 configuration and plugin directory.
4. Remove `cli.json` from the active V1 configuration directory.
5. Restore `tui.json(c)` from the backup.
6. Restart the prior ai-memory service and confirm its loopback MCP endpoint.

Do not start V1 with the converted native V2 configuration.

For this first cutover, the V2 diagnostic touched the shared database before the database-backup rule existed. The backed-up V1 binary starts against an isolated copy of the migrated database, but it does not list the prior sessions. Treat exact V1 session rollback as an open risk; the V2 database and session API remain the current recovery sources.

## Acceptance

The migration is not complete until the laptop and phone web checks, remote TUI check, shared-session check, two-worktree isolation check, permission prompt check, plugin/MCP checks, service restart, login-after-reboot check, and two-run idempotency check all pass. Learn and RTK remain explicit blockers for full feature parity.
