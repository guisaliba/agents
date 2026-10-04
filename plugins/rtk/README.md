# RTK

## Status

This repository installs a temporary RTK adapter for OpenCode V2. An adapter is
a plugin that changes a shell command by calling RTK before the shell tool runs.
The official RTK V2 pull request is still open. The latest stable RTK release
checked for this change is `v0.50.0`; it does not include the V2 plugin.

The RTK command-line program remains separate from the plugin. Use it as usual:

```sh
rtk rewrite "git status --short"
rtk gain
rtk <command>
```

## Pinned source

`rtk.ts` is an unchanged copy of this source file:

| Item | Value |
| --- | --- |
| RTK pull request | [rtk-ai/rtk#4187](https://github.com/rtk-ai/rtk/pull/4187) |
| Source repository | [amnesiaof/rtk](https://github.com/amnesiaof/rtk) |
| Source commit | `df86d7e0683844de7a09539589e6794f7f6a62e8` |
| Source path | [`hooks/opencode/rtk.ts`](https://github.com/amnesiaof/rtk/blob/df86d7e0683844de7a09539589e6794f7f6a62e8/hooks/opencode/rtk.ts) |
| Git blob SHA | `a6da9a687e4d2c886eaed8ac366a2940faac871e` |
| SHA-256 | `601875c939db05c58d86d7be788f9c329c9de490faf09f30c97703cc271d4339` |
| License | Apache-2.0; see [`LICENSE`](LICENSE) |

The default export has the OpenCode V2 `id` and `setup` fields. It also keeps
the source's V1 `server()` compatibility method. The file uses Node built-ins;
it adds no npm or OpenCode SDK dependency.

Tracking this plugin is a temporary exception to this repository's normal rule
against vendored plugin payloads. Do not edit `rtk.ts`. Replace it only after an
official stable RTK release passes the checks at the end of this document.

## Install

`./apply.sh` installs the tracked file at:

```text
~/.config/opencode/plugins/rtk.ts
```

OpenCode V2 discovers direct plugin files in this global plugin directory, as
described in the [plugin guide](https://opencode.ai/v2/docs/plugins). The apply
path does not add RTK to the `plugins` config list. It removes RTK package or
file entries from that list, and it keeps unrelated entries.

The installer uses the repository's guarded file check and atomic write helper.
The atomic write writes a complete temporary file before it replaces the target.
It rejects a symlink or non-directory in the config path. It also rejects
another discovered local plugin file or package that declares `id: "rtk"`. It
also rejects a local `rtk.js` or `rtk/` entry. When a different regular `rtk.ts`
is present, it first saves that file under:

```text
~/.local/share/opencode/plugin-backups/rtk.ts.<UTC-time>.<random>
```

This backup is outside the plugin discovery directory. An identical tracked
file is not rewritten or backed up again.

The apply path checks the RTK CLI separately from the plugin file. A new CLI
install uses the pinned stable release `v0.50.0`. An existing stable CLI stays
installed when it passes a version and rewrite check. The verified local CLI
`0.38.0` passes that check, so apply does not downgrade it. The installer does
not run `rtk init -g --opencode`. A new install accepts only a stable `vX.Y.Z`
tag. It rejects branches and prereleases.

## Behavior and limits

The V2 plugin registers `execute.before`. It considers only `bash` or `shell`
tools, without case sensitivity, and only a nonblank string command. It finds
RTK through `RTK_BIN`, `PATH`, and the source's fallback directories. It runs
RTK directly with `rewrite` and the original command. The timeout is 3 seconds.

The plugin uses trimmed, nonempty output that differs from the original command
when RTK exits with code 0 or 3. Missing RTK, launch errors, other exit codes,
signals, and timeouts leave the command unchanged. The plugin also rejects
partial output after a signal or timeout.

This is command compaction, not a security policy. The plugin discards RTK deny
and defer results. OpenCode's own [shell permission checks](https://opencode.ai/v2/docs/permissions)
remain active. On RTK errors, the original command continues unchanged. This is
fail-open behavior: a helper failure does not stop the command. Do not use this
plugin as an authorization control.

## Tool host and reload

Install RTK and this plugin on every host that runs OpenCode tools. This can be a
client running a local TUI, or the server running a web or phone session. This
change does not connect local TUIs to the server or change the current topology.

OpenCode also discovers project plugins under each project's `.opencode/plugins`
directory. The pinned source has the fixed ID `rtk`. A project plugin with that
same ID conflicts with the global adapter: the tested OpenCode 2.0.18 loader
keeps the global adapter and does not initialize the project copy. The apply
script can inspect the global plugin directory, but it cannot inspect every
project workspace on the host. Do not use two RTK plugins with ID `rtk` in one
OpenCode location. A different ID needs a different source payload.

The normal apply path installs both the CLI and plugin before its existing
server start point. At plugin setup, a missing RTK CLI means the plugin registers
no hook. If RTK is installed later, reload or restart the OpenCode process that
runs tools through its existing lifecycle. If apply installs RTK while the
plugin file already matches, it logs this reload requirement and does not touch
the file or restart a service. The [plugin guide](https://opencode.ai/v2/docs/plugins)
describes plugin discovery and reload. Do not stop a shared server or active
session without a safe restart plan.

## Verify

`./test.sh --repo-only` runs the isolated apply fixtures and the Bun tests.
`smoke-test.py` starts the supported OpenCode CLI with `--standalone`, an
isolated home, an isolated Git workspace, and a local OpenAI-compatible test
provider. It loads this exact local file and runs a real shell tool. It uses no
provider credential and no auto-approval. The test asks for shell permission by
default and allows only the original and rewritten smoke commands.

See [`verification.md`](verification.md) for the tested versions and output.
Run the smoke test with stable OpenCode V2 and a compatible stable RTK CLI:

```sh
TMPDIR=<private-temporary-directory> \
OPENCODE_BIN=<path-to-opencode> \
RTK_BIN=<path-to-rtk> \
python3 plugins/rtk/smoke-test.py
```

Set `RTK_SMOKE_PROJECT_PLUGIN_ID` to test project/global ID collisions. A unique
ID loads beside the global adapter. The ID `rtk` does not:

```sh
RTK_SMOKE_PROJECT_PLUGIN_ID=project.test python3 plugins/rtk/smoke-test.py
RTK_SMOKE_PROJECT_PLUGIN_ID=rtk python3 plugins/rtk/smoke-test.py
```

The script supports macOS and Linux. The recorded runtime test used macOS arm64.
The runtime test has not been run on Linux or Windows. Windows is not a required
target for this plugin.

## Uninstall and rollback

To remove the tracked plugin, first check that the installed file is the tracked
payload, then remove it and reload the tool-running OpenCode process:

```sh
cmp plugins/rtk/rtk.ts ~/.config/opencode/plugins/rtk.ts && \
  rm ~/.config/opencode/plugins/rtk.ts
```

The RTK CLI stays installed for normal command use. To restore the file that was
replaced, copy the selected backup from
`~/.local/share/opencode/plugin-backups/` to
`~/.config/opencode/plugins/rtk.ts`, then reload the tool-running process. A
restored V1 plugin does not provide V2 behavior.

## Replace this adapter with an official release

1. Confirm an official stable RTK release contains a working V2 default export
   and rewrite hook. A merged pull request or prerelease is not enough.
2. Compare the released behavior with this adapter. Run the loader, rewrite,
   timeout, fail-open, and permission checks.
3. Back up the installed temporary file. Remove this payload and its temporary
   installer and test assumptions in a reviewable change.
4. Update the CLI pin. Use the official release's documented plugin installer.
   Re-enable `rtk init -g --opencode` only if it generates a V2-compatible
   plugin and remains the documented install method.
5. Check that exactly one official RTK plugin loads. Remove old local or config
   entries. Reload the process that runs tools through its existing lifecycle.
6. Re-run apply, idempotency, and runtime tests. Keep a tested rollback to this
   pinned adapter in case the official behavior regresses.
