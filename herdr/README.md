# Herdr

Herdr 0.9.0 gives one terminal view of independent Linux and macOS execution
hosts. Each
selected operating-system user has one default Herdr session on each host.
Projects and tasks use workspaces, tabs, and panes in that session. Each host
runs its own Herdr server, OpenCode process, files, credentials, and ai-memory
data.

The laptop client lists Local, the VPS, and the home computer. The VPS client
lists Local, the laptop, and the home computer. Configure each list separately.
A machine profile targets one host session. It does not import the profile list
from that host.

Tailscale provides the private network. SSH provides host authentication. Herdr
does not synchronize files, memory databases, credentials, or selected tabs.

## Install

The normal agent-stack apply includes Herdr:

```sh
./apply.sh
./test.sh
```

On an already configured OpenCode host, use the focused pilot path:

```sh
./herdr/apply.sh
```

The focused path installs the verified `~/.local/bin/herdr` release, merges the
Herdr config, runs the official OpenCode integration, updates the managed Bash
block and global instructions, and installs only the Herdr skill. It does not
restart ai-memory, update Learn, refresh other plugins, enroll machines, or
retire another remote-access service.

The installer accepts Linux `x86_64` and `aarch64`, and macOS `x86_64` and
`arm64`. It rejects Android and Termux before download. It verifies the pinned
SHA-256 value and `herdr --version` before an atomic replacement. It keeps an
older managed executable in `~/.local/state/agents/herdr/backups/`. It does not
replace an executable owned by another installation path and does not downgrade
a newer version.

The managed config is `~/.config/herdr/config.toml`:

```toml
[terminal]
default_shell = "/resolved/path/to/bash"
shell_mode = "non_login" # "login" on macOS

[session]
resume_agents_on_restore = false
```

The actual Bash executable is resolved on each host. macOS uses Homebrew Bash
in login mode. Other valid TOML settings and comments stay in the file. The
installer does not restart a running Herdr server.

## OpenCode Integration

Setup runs only the official commands:

```sh
herdr integration install opencode
herdr integration status
```

Herdr 0.9.0 supplies OpenCode integration version 11. See
[`../plugins/herdr/README.md`](../plugins/herdr/README.md) for file ownership.
The integration is inactive outside a Herdr pane.

The Herdr control socket can control other panes. The default ai-jail mounts do
not expose it. Ordinary managed launches work first; a jailed launch can have a
separate Herdr-control limitation.

## Enroll Hosts

Installation and enrollment are separate. Keep real host names, account names,
profile IDs, session IDs, and service details in the private rollout record.
First inspect the local client list:

```sh
herdr machine list --json
```

Compare `target` and `session`, not only `label`. Add only a missing verified
target:

```sh
herdr machine add <ssh-target> --label <display-name>
```

The remote session defaults to `default`. Use `--remote-session` only to keep a
documented existing named session. To change a label, read the profile ID from
the list and run:

```sh
herdr machine rename <profile-id> --label <display-name>
```

Profile and pane IDs are local to one Herdr server. Read each ID from command
output. UI focus on a remote machine does not redirect a CLI command in another
pane.

If setup reports Attention, use its interactive setup command and complete the
real SSH host-key or authentication check. Keep normal SSH verification. For
WSL2, first verify systemd user services, SSH access, and persistence. Native
Android, Termux, Windows clients, and Windows SSH targets are not supported in
combined machine mode.

## Daily Use

Start or attach the default client:

```sh
herdr
```

In an interactive Herdr Bash pane, the managed function is sufficient:

```sh
opencode
```

For automation, create or select a shell pane and use the explicit command. Do
not assume that a subprocess can see the unexported Bash function:

```sh
HERDR_AGENT=opencode ai-memory run opencode
```

For agent-driven control, create a shell pane, read its returned pane ID,
confirm that it is available, and then run:

```sh
herdr pane run <pane-id> "HERDR_AGENT=opencode ai-memory run opencode"
```

Do not use `herdr agent start` as the standard managed path. Its native
arguments do not select an ai-memory workstream.

Detach with the configured Herdr detach binding. Reconnect with `herdr`. A live
detach or SSH logout keeps the host process and workstream lease. A sleeping or
powered-off host cannot run agents.

For phone access, connect the phone SSH client to the VPS through Tailscale and
run `herdr` on the VPS. The phone does not install Herdr or OpenCode.

## Task Isolation

Use one named workstream for each independent task. Use a separate Git worktree
for each OpenCode task that runs at the same time:

```sh
# Run from the task-a worktree.
HERDR_AGENT=opencode ai-memory run --new herdr-task-a opencode

# Run from the task-b worktree.
HERDR_AGENT=opencode ai-memory run --new herdr-task-b opencode
```

Run each command in a separate pane from its task worktree. Wrapper options go
before `opencode`. Native OpenCode arguments go after it. One writer owns a
workstream at a time. Keep its lease; a second writer must fail.

With the current ai-memory OpenCode adapter, a new session has no caller-chosen
ID. After the process exits, the adapter can select a newer active OpenCode
session from the same checkout. A separate worktree gives each concurrent task
a different recorded directory and prevents this cross-link.
`--fresh` does not remove this same-checkout discovery risk and does not
isolate tasks.

## Restart Recovery

Automatic native-agent restoration is disabled because Herdr normally restores
OpenCode with a native session ID and does not include the ai-memory workstream
name. After a full Herdr server or host restart, restore the layout and resume
each task explicitly:

```sh
cd <task-worktree>
HERDR_AGENT=opencode ai-memory run --workstream herdr-task-a opencode
```

Use the recorded task worktree and workstream name. Do not use `--fresh`
unless a new native conversation is intended.

## Future Harnesses

Herdr is independent of OpenCode. Install a future coding harness beside
OpenCode with its own provider login and its own optional Herdr integration.
Keep its managed-launch and memory contract separate. OpenCode remains the only
installed coding harness for this rollout.

## Rollback

Remove only the upstream OpenCode integration with:

```sh
herdr integration uninstall opencode
```

Restore the recorded Herdr config, executable, and Bash block from the private
backups. Remove only profiles created during the rollout. Removing a machine
profile disconnects that client and does not stop remote agents.
