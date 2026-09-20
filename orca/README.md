# Orca Remote Server

`apply.sh` installs the official Stably Orca Homebrew cask on macOS and manages
the M4 remote server as a root-owned LaunchDaemon. Linux hosts do not install or
run the server.

The validated release is Orca `1.4.205`. Apply does not upgrade an existing
installation. Upgrades are explicit maintenance operations.

## Runtime Contract

The service runs as the user who generated the plist:

```text
/opt/homebrew/bin/orca serve \
  --port 6768 \
  --pairing-address aurealabs-mac-mini-m4.taildc6550.ts.net \
  --no-pairing
```

The managed files are:

```text
~/.config/orca-server/com.stablyai.orca-server.plist
/Library/LaunchDaemons/com.stablyai.orca-server.plist
~/Library/Logs/orca-server/stdout.log
~/Library/Logs/orca-server/stderr.log
~/.config/orca-server/com.stablyai.orca-server.pf
~/.config/orca-server/pf.conf
~/.config/orca-server/pf.conf.without-orca
~/.config/orca-server/com.stablyai.orca-firewall.plist
/etc/pf.anchors/com.stablyai.orca-server
/Library/LaunchDaemons/com.stablyai.orca-firewall.plist
```

The generated source plist has mode `0600`. The installed plist must be
`root:wheel` with mode `0644`. The log directory has mode `0700`, and each log
file has mode `0600`. The service sets a deterministic `HOME` and `PATH`, starts
at boot after FileVault unlock, uses `KeepAlive`, and has a 10-second restart
throttle.

Apply stops when privileged installation is necessary and prints the required
commands. It does not use hidden or passwordless `sudo`.

## Network Boundary

Port `6768` is for private Tailscale access only. Do not publish it to the
internet or add a public ingress rule. ai-memory remains on its M4 loopback
endpoint. Orca clients control agents on the M4; they do not connect to
ai-memory directly.

Orca listens on all interfaces and has no bind-address option. The managed PF
anchor permits TCP port `6768` only from the Tailscale IPv4 range
`100.64.0.0/10` and IPv6 range `fd7a:115c:a1e0::/48`, then blocks all other
sources. A separate root-owned one-shot LaunchDaemon loads `/etc/pf.conf`,
enables PF, and records the loaded Orca anchor rules at each boot. Apply
preserves existing PF content and maintains one marked Orca anchor block.

Pairing links are bearer credentials. Use them only in a controlled foreground
session. Do not put them in source control, shell history, normal service logs,
test output, or memory.

The initial rollout proved that the `osarchy` desktop grant and the `Aurea M4`
mobile grant survive a restart with `--no-pairing`.

## Pair A Client

Stop the service before a controlled pairing session:

```sh
sudo launchctl bootout system/com.stablyai.orca-server
orca serve --port 6768 \
  --pairing-address aurealabs-mac-mini-m4.taildc6550.ts.net
```

Use a separate controlled session with `--mobile-pairing` for a phone. Do not
combine runtime-environment pairing and mobile pairing in one process start.
After pairing, stop the foreground process and restore the service:

```sh
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/com.stablyai.orca-server.plist
sudo launchctl kickstart -k system/com.stablyai.orca-server
```

Confirm that all established clients reconnect while the server uses
`--no-pairing`.

## Verify

On the M4:

```sh
orca --version
sudo launchctl print system/com.stablyai.orca-server
sudo launchctl print system/com.stablyai.orca-firewall
sudo pfctl -s info
sudo pfctl -a com.stablyai.orca-server -sr
lsof -nP -iTCP:6768 -sTCP:LISTEN
stat -f '%Su:%Sg:%Lp' \
  /Library/LaunchDaemons/com.stablyai.orca-server.plist
```

On a paired desktop client:

```sh
stably-orca status --environment "M4 Server" --json
```

The runtime must report `ready`, `reachable`, and `connected`. The live M4
test also proved that launchd starts a new Orca process and clients reconnect
after the listener process exits.

## Reboot Acceptance

FileVault must be unlocked before macOS, Tailscale, SSH, or the managed
LaunchDaemons can start. Do not start a remote reboot test without confirmed
physical access or a separately validated authenticated-restart procedure.

To prove that the system LaunchDaemons do not depend on GUI login, separate the
FileVault unlock from GUI login before the test:

```sh
sudo defaults write /Library/Preferences/com.apple.loginwindow \
  DisableFDEAutoLogin -bool YES
sudo reboot
```

At startup, unlock FileVault with an authorized local account and remain at the
macOS login screen. If Tailscale starts before GUI login, verify the services
remotely there. Otherwise, log in and use boot logs and process start times to
confirm that PF, ai-memory, and Orca started before the GUI session. Also verify
that paired clients reconnect and existing Orca terminals remain recoverable.

## Parallel Work

Use one Orca Git worktree for each concurrent task. ai-memory gives each
worktree an independent managed workstream while all worktrees can read shared
project memory. Do not add an Orca wrapper, custom lock, or naming workaround.
Two agents must not own the same ai-memory workstream at the same time.

## Upgrade

Use a maintenance window because an upgrade interrupts active sessions:

```sh
brew upgrade --cask stablyai/orca/orca
sudo launchctl kickstart -k system/com.stablyai.orca-server
```

Rerun `./apply.sh` and the verification steps after the upgrade. Orca serve
does not run an automatic updater.

## Known Limits

Remote Orca Server is beta. Current upstream macOS limits include:

- [Issue 15537](https://github.com/stablyai/orca/issues/15537) and
  [PR 15560](https://github.com/stablyai/orca/pull/15560): opening the desktop
  app and pressing Command-Q can stop serve mode. launchd restarts the process.
- [Issue 16061](https://github.com/stablyai/orca/issues/16061): serve mode can
  show a Dock icon. Do not modify or re-sign Orca to hide it.

The validated system LaunchDaemon is the selected service model. If a future
Orca release cannot run in the system launchd domain, use a user LaunchAgent as
the fallback. This requires one GUI login after a reboot. Keep FileVault
enabled, and do not enable automatic login.

## Rollback

Remove only the managed service and installed plist:

```sh
sudo launchctl bootout system/com.stablyai.orca-server 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/com.stablyai.orca-server.plist
sudo launchctl bootout system/com.stablyai.orca-firewall 2>/dev/null || true
sudo install -o root -g wheel -m 0644 \
  "$HOME/.config/orca-server/pf.conf.without-orca" /etc/pf.conf
sudo rm -f /etc/pf.anchors/com.stablyai.orca-server
sudo rm -f /Library/LaunchDaemons/com.stablyai.orca-firewall.plist
sudo pfctl -f /etc/pf.conf
```

This rollback preserves repositories, worktrees, Orca state, paired-client
grants, credentials, logs, the generated source plist, and all ai-memory data.
It does not disable PF because other system services can own enable references.
Remove the Homebrew cask only when Orca itself is no longer required.
