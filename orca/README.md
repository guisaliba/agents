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

The root-owned `com.stablyai.orca-firewall` LaunchDaemon is the startup gate.
The gate runs at load and every 60 seconds. Each run does this work:

1. Stop Orca when the gate cannot prove the required firewall state.
2. Load `/etc/pf.conf` and enable PF when the live state is not current.
3. Read the live Orca anchor and compare it with the expected anchor rules.
4. Publish current-boot evidence only after the comparison succeeds.
5. Enable, load, and start the Orca service only after the comparison succeeds.

The Orca service runs a root-owned preflight script as the selected user. The
preflight refuses to execute Orca unless the gate evidence belongs to the
current boot and matches the expected anchor rules. Orca therefore cannot
listen on TCP `6768` before the gate succeeds. The design fails closed: a
missing anchor, an invalid PF configuration, a disabled PF, or a failed gate
run leaves Orca stopped.

The managed files are:

```text
~/.config/orca-server/com.stablyai.orca-server.plist
/Library/LaunchDaemons/com.stablyai.orca-server.plist
~/Library/Logs/orca-server/stdout.log
~/Library/Logs/orca-server/stderr.log
~/.config/orca-server/com.stablyai.orca-server.sh
/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-server.sh
~/.config/orca-server/com.stablyai.orca-server.pf
~/.config/orca-server/pf.conf
~/.config/orca-server/pf.conf.without-orca
~/.config/orca-server/pf.conf.sha256
~/.config/orca-server/com.stablyai.orca-firewall.sh
/usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-firewall.sh
~/.config/orca-server/com.stablyai.orca-firewall.plist
~/.config/orca-server/install-privileged.sh
/etc/pf.anchors/com.stablyai.orca-server
/Library/LaunchDaemons/com.stablyai.orca-firewall.plist
/var/run/com.stablyai.orca-server.gate
```

Generated source files have mode `0600`. The installed plists and the anchor
file must be `root:wheel` with mode `0644`. The installed gate and preflight
scripts must be `root:wheel` with mode `0755`. The evidence file must be
`root:wheel` with mode `0644`. The log directory has mode `0700`, and each log
file has mode `0600`. The Orca service sets a deterministic `HOME` and `PATH`,
starts at boot after FileVault unlock, uses `KeepAlive`, and has a 10-second
restart throttle. The preflight runs on every Orca start and restart.

Apply stops when privileged installation is necessary and writes
`~/.config/orca-server/install-privileged.sh`. Inspect that script and run
`sudo bash ~/.config/orca-server/install-privileged.sh`. Apply does not use
hidden or passwordless `sudo`.

Apply records the SHA-256 of `/etc/pf.conf` in
`~/.config/orca-server/pf.conf.sha256` when it generates the Orca sources. The
privileged install script compares the current file with that digest before it
changes anything. A mismatch stops the script with a non-zero status and
installs nothing. Rerun `./apply.sh` to regenerate the sources from the new
file.

After the install, the script removes any earlier evidence file and waits for
the gate to publish evidence for the current boot that also carries the
expected anchor hash. It reports success only after that evidence appears.

## Network Boundary

Port `6768` is for private Tailscale access only. Do not publish it to the
internet or add a public ingress rule. ai-memory remains on its M4 loopback
endpoint. Orca clients control agents on the M4; they do not connect to
ai-memory directly.

Orca listens on all interfaces and has no bind-address option. The managed PF
anchor permits TCP port `6768` only from the Tailscale IPv4 range
`100.64.0.0/10` and IPv6 range `fd7a:115c:a1e0::/48`, then blocks all other
sources, including the loopback interface and the LAN. Apply preserves existing
PF content and maintains one marked Orca anchor block.

Apply places the managed anchor at the start of the filtering section of
`/etc/pf.conf`: after the system normalization and translation anchors, and
before every filter rule. PF requires that rule order. An earlier `pass ...
quick` rule cannot skip the anchor. The anchor and the whole generated
configuration are parsed with `pfctl -nf` before installation.
The pass rules also require the Tailscale `utun*` interface, so a local network
that uses the same address ranges cannot match them.

The root-owned gate is the only component that starts Orca. It loads
`/etc/pf.conf`, enables PF, compares the live anchor with the expected anchor,
and checks that the live main ruleset calls the Orca anchor before every other
filter rule. It publishes current-boot evidence only after those checks pass.
The Orca preflight then checks that evidence before it executes Orca. This
ordering removes the boot window in which the port could listen before the
rules are active.

When the live state does not match, the gate stops Orca first, then reloads
`/etc/pf.conf`. Stopping Orca closes any session that an earlier rule allowed,
and the reload does not preserve those sessions. Orca starts again only after
the reloaded state matches; if it still does not match, Orca stays stopped. A
later PF load that moves the anchor behind an earlier quick rule is therefore
detected and repaired within one gate cycle.

Pairing links are bearer credentials. Use them only in a controlled foreground
session. Do not put them in source control, shell history, normal service logs,
test output, or memory.

The initial rollout proved that the `osarchy` desktop grant and the `Aurea M4`
mobile grant survive a restart with `--no-pairing`.

## Pair A Client

Stop the gate and the service before a controlled pairing session. The gate
runs every 60 seconds and restarts the service, so it must not stay loaded:

```sh
sudo launchctl bootout system/com.stablyai.orca-firewall 2>/dev/null || true
sudo launchctl bootout system/com.stablyai.orca-server 2>/dev/null || true
orca serve --port 6768 \
  --pairing-address aurealabs-mac-mini-m4.taildc6550.ts.net
```

Use a separate controlled session with `--mobile-pairing` for a phone. Do not
combine runtime-environment pairing and mobile pairing in one process start.
After pairing, stop the foreground process and restore the gate. The gate
validates PF, starts the service, and re-enables it:

```sh
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/com.stablyai.orca-firewall.plist
sudo launchctl kickstart -k system/com.stablyai.orca-firewall
```

Confirm that all established clients reconnect while the server uses
`--no-pairing`.

## Verify

On the M4:

```sh
orca --version
launchctl print system/com.stablyai.orca-server
launchctl print system/com.stablyai.orca-firewall
sudo pfctl -s info
sudo pfctl -a com.stablyai.orca-server -sr
cat /var/run/com.stablyai.orca-server.gate
sysctl -n kern.bootsessionuuid
lsof -nP -iTCP:6768 -sTCP:LISTEN
stat -f '%Su:%Sg:%Lp' \
  /Library/LaunchDaemons/com.stablyai.orca-server.plist \
  /Library/LaunchDaemons/com.stablyai.orca-firewall.plist \
  /usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-server.sh \
  /usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-firewall.sh \
  /var/run/com.stablyai.orca-server.gate
```

The evidence file must record `bootsession` equal to `kern.bootsessionuuid`
and the `anchor_sha256` of the live anchor rules. A run of `./test.sh` checks
these values and the listener. The evidence from an earlier boot is not proof.

On a paired desktop client:

```sh
stably-orca status --environment "M4 Server" --json
```

The runtime must report `ready`, `reachable`, and `connected`. The live M4
test also proved that launchd starts a new Orca process and clients reconnect
after the listener process exits.

## Fail-Closed Checks

Test the gate behavior on the M4 with controlled changes:

```sh
# Disable PF. Orca must stop within one gate cycle (60 seconds).
sudo pfctl -d

# Restore PF. The gate repairs the state and starts Orca again.
sudo launchctl kickstart -k system/com.stablyai.orca-firewall
```

To prove the boot path from a clean state, unload both jobs, remove the
evidence file, and load only the gate. Orca must not listen until the gate
publishes evidence:

```sh
sudo launchctl bootout system/com.stablyai.orca-server 2>/dev/null || true
sudo launchctl bootout system/com.stablyai.orca-firewall 2>/dev/null || true
sudo rm -f /var/run/com.stablyai.orca-server.gate
sudo launchctl bootstrap system \
  /Library/LaunchDaemons/com.stablyai.orca-firewall.plist
sudo launchctl kickstart -k system/com.stablyai.orca-firewall
lsof -nP -iTCP:6768 -sTCP:LISTEN
```

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
confirm that PF, ai-memory, and Orca started before the GUI session.

The gate holds Orca stopped until it proves the required PF state. The
per-boot sequence is:

1. The gate loads `/etc/pf.conf`, enables PF, and compares the live anchor.
2. The gate publishes evidence for the current boot.
3. The gate starts the Orca service.
4. The Orca preflight reads the evidence before it executes Orca.

Old evidence cannot start Orca after a reboot because the boot session changes.
Also verify that paired clients reconnect and existing Orca terminals remain
recoverable.

## Parallel Work

Use one Orca Git worktree for each concurrent task. ai-memory gives each
worktree an independent managed workstream while all worktrees can read shared
project memory. Do not add an Orca wrapper, custom lock, or naming workaround.
Two agents must not own the same ai-memory workstream at the same time.

## Upgrade

Use a maintenance window because an upgrade interrupts active sessions:

```sh
brew upgrade --cask stablyai/orca/orca
sudo launchctl kickstart -k system/com.stablyai.orca-firewall
```

The gate kickstart revalidates PF and restarts the Orca service. Rerun
`./apply.sh` and the verification steps after the upgrade. Orca serve does not
run an automatic updater.

## Known Limits

Remote Orca Server is beta. Current upstream macOS limits include:

- [Issue 15537](https://github.com/stablyai/orca/issues/15537) and
  [PR 15560](https://github.com/stablyai/orca/pull/15560): opening the desktop
  app and pressing Command-Q can stop serve mode. launchd restarts the process.
- [Issue 16061](https://github.com/stablyai/orca/issues/16061): serve mode can
  show a Dock icon. Do not modify or re-sign Orca to hide it.

The gate revalidates PF every 60 seconds. A PF change that another process makes
is repaired within one interval, and Orca stops when the repair fails. The
evidence file is current-boot data, not a durable certificate. Do not copy it
between boots.

The validated system LaunchDaemon is the selected service model. If a future
Orca release cannot run in the system launchd domain, use a user LaunchAgent as
the fallback. This requires one GUI login after a reboot. Keep FileVault
enabled, and do not enable automatic login.

## Rollback

Remove only the managed services and installed files. The first command refuses
the restore when `/etc/pf.conf` changed after apply generated the rollback file:

```sh
sudo launchctl disable system/com.stablyai.orca-server
sudo launchctl bootout system/com.stablyai.orca-server 2>/dev/null || true
sudo launchctl bootout system/com.stablyai.orca-firewall 2>/dev/null || true
test "$(shasum -a 256 /etc/pf.conf | awk '{print $1}')" = \
  "$(shasum -a 256 "$HOME/.config/orca-server/pf.conf" | awk '{print $1}')" && \
  sudo install -o root -g wheel -m 0644 \
    "$HOME/.config/orca-server/pf.conf.without-orca" /etc/pf.conf && \
  sudo pfctl -f /etc/pf.conf && \
  sudo rm -f /etc/pf.anchors/com.stablyai.orca-server \
    /Library/LaunchDaemons/com.stablyai.orca-firewall.plist \
    /Library/LaunchDaemons/com.stablyai.orca-server.plist \
    /usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-firewall.sh \
    /usr/local/libexec/com.stablyai.orca-server/com.stablyai.orca-server.sh \
    /var/run/com.stablyai.orca-server.gate || \
  printf 'ERROR: /etc/pf.conf changed since apply generated the Orca sources; the restore and cleanup did not run. Fix the file or rerun apply.sh.\n' >&2
```

This rollback preserves repositories, worktrees, Orca state, paired-client
grants, credentials, logs, the generated source files, and all ai-memory data.
It does not disable PF because other system services can own enable references.
Remove the Homebrew cask only when Orca itself is no longer required.
