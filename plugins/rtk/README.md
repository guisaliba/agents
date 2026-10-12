# RTK

## Status

This repository installs a temporary RTK adapter for OpenCode V2. An adapter is
a plugin that changes a shell command by calling RTK before the shell tool runs.
The official [RTK V2 PR #4187](https://github.com/rtk-ai/rtk/pull/4187)
merged on **12 October 2026 at 07:21:45 UTC**. Stable replacement is still pending.
The latest official stable release checked on 12 October is
[`v0.51.0`](https://github.com/rtk-ai/rtk/releases/tag/v0.51.0). Its
[source payload](https://github.com/rtk-ai/rtk/blob/v0.51.0/hooks/opencode/rtk.ts)
is V1-only. The stable tag is not a descendant of the V2 merge, and the payload
has no equivalent V2 implementation.

**Forecast:** `v0.52.0` is the likely next stable target. Upstream publishes
[`dev-0.52.0-rc.525`](https://github.com/rtk-ai/rtk/releases/tag/dev-0.52.0-rc.525);
the [release policy](https://github.com/rtk-ai/rtk/blob/master/release-please-config.json)
bumps the minor version for pre-1.0 features. This is not a confirmed stable
version or publication date. Keep the temporary adapter until stable validation.

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

## Upstream merge evidence

The [merge commit](https://github.com/rtk-ai/rtk/commit/311ebcbfd8efdb09b03219e7615a153b5b5e3c97)
is `311ebcbfd8efdb09b03219e7615a153b5b5e3c97`. Its
[plugin](https://github.com/rtk-ai/rtk/blob/311ebcbfd8efdb09b03219e7615a153b5b5e3c97/hooks/opencode/rtk.ts)
has blob SHA `a523caf3e2b8540202491d5e5e6ed11f4f3fb95f`, identical to the
checked develop payload. The PR body describes an older design; use this code.

| Contract | Temporary adapter | Merged upstream |
| --- | --- | --- |
| V2 loader | Default object `id/setup` | Same working shape |
| Command mutation | `execute.before` changes `event.input.command` | Same, restricted to bash/shell and nonblank strings |
| Transport | `rtk rewrite <command>` | Shell-free `rtk hook opencode [--agent <name>] <command>` |
| Output | Trimmed changed stdout, exit 0/3 | JSON command on exit 0; any nonzero exit, including 3, passes through |
| Binary | RTK_BIN, PATH and fallback directories | PATH only, Windows PATHEXT; skips directories |
| Setup | Found binary | Also probes `hook opencode --help` once per usable binary |
| Failure | Missing binary/error/signal/timeout passes through | Missing or incompatible binary registers no hook; error/timeout/invalid JSON passes through |
| Timeout | 3 seconds | 3 seconds for probe and hook |
| Permissions | Generic rewrite; OpenCode evaluates final command | Forwards V2 agent name and tries to preserve OpenCode rule verdict |
| Session off switch | No plugin environment check | OpenCode process `RTK_DISABLED=1` skips rewrites |

The [Rust protocol](https://github.com/rtk-ai/rtk/blob/311ebcbfd8efdb09b03219e7615a153b5b5e3c97/src/hooks/hook_cmd.rs)
returns JSON with exit 0 for rewrite and passthrough. Thus exit-3 rejection is a
transport change, not an unchanged copy of the temporary exit-3 contract.
An old CLI can pass this repository's rewrite probe but lack the new subcommand.

[Node tests](https://github.com/rtk-ai/rtk/blob/311ebcbfd8efdb09b03219e7615a153b5b5e3c97/hooks/opencode/rtk.test.mjs)
cover both hook shapes, command mutation, exact argv, agent forwarding, absent
or old binary, capability caching, off switch, guards, invalid JSON, failure and
timeout. These use a mock context; they do not prove real V2 loader execution on
this repository's hosts.
[Installer tests](https://github.com/rtk-ai/rtk/blob/311ebcbfd8efdb09b03219e7615a153b5b5e3c97/src/hooks/init/opencode.rs)
cover embedded payload installation and the OpenCode 1.18.29 floor.

Permission parity is not guaranteed. Check follow-ups
[#4522](https://github.com/rtk-ai/rtk/pull/4522) (global config lookup),
[#4528](https://github.com/rtk-ai/rtk/pull/4528) (JSONC),
[#4533](https://github.com/rtk-ai/rtk/pull/4533) (Windows discovery), and
[#4534](https://github.com/rtk-ai/rtk/pull/4534) (installer probe).
Verify their status and inclusion in the selected stable tag.

## Replace this adapter with an official release

This handoff changes documentation only. Main contains the temporary payload
and its pinned blob matches the provenance above. This does not prove that any
host has run apply.

1. **Verify a stable payload first.** Select an official non-draft,
   non-prerelease tag. Inspect its V2 default object, hook, command mutation,
   CLI hook capability and embedded installer payload. Generate the plugin in
   an isolated home. The merged installer uses `rtk init -g --opencode`; use
   that command only if the chosen stable release still generates verified V2
   code. A merge or release candidate is not enough.
2. **Prepare a later implementation PR.** Remove the tracked temporary
   `plugins/rtk/rtk.ts` and source-specific tests after equivalent official
   tests exist. Replace `apply.sh:install_rtk_plugin` and its call with the
   official flow. Preserve guarded writes, backup and duplicate detection.
   Update RTK config cleanup and `test.sh` assumptions that require the pinned
   blob or `v0.50.0`, or forbid official init. Keep provenance documentation.
3. **Update CLI pin and capability checks.** Set `RTK_VERSION` to the verified
   stable tag. Update `install_rtk`: its current rewrite check retains old
   CLIs. Require the stable minimum and `rtk hook opencode --help`, or the new
   plugin can disable itself. Ensure the tool host's PATH selects that binary;
   upstream does not honor RTK_BIN or fallback directories.
4. **Back up on each shell-tool host.** Save the installed regular
   `~/.config/opencode/plugins/rtk.ts`, its digest and CLI version under
   `~/.local/share/opencode/plugin-backups/`, outside plugin discovery.
   If absent, record that fact and treat the official installation as fresh.
5. **Install one official plugin.** After the implementation change, install
   the verified stable CLI and use its documented plugin installer. Remove
   obsolete global/config/project registrations, `rtk.js`, `rtk/` and other
   modules with ID `rtk`. Preserve unrelated plugins. Do not run the current
   apply after replacement: it restores the temporary payload.
6. **Reload the tool host through its existing lifecycle.** Local TUI and
   remote server tool hosts can differ. Coordinate shared-service restarts.
   Preserve topology and OpenCode permissions; do not add Orca.
7. **Verify behavior.** Run revised `./test.sh --repo-only` fixtures and adapt
   `plugins/rtk/smoke-test.py`, which currently loads the tracked file, to
   exercise the generated official file with a real V2 loader and shell tool.
   Check shell-only mutation; agent/global/project allow/ask/deny and JSONC
   rules; missing/incompatible binary; launch error; invalid JSON; timeout
   with partial stdout; and session off switch. Check generic rewrite exit
   0/3 separately from official JSON exit 0 and nonzero exit-3 passthrough.
   Run apply twice: content must remain stable without extra backups or
   duplicate registrations.
8. **Test rollback.** Restore the prior agents revision, compatible CLI and
   backed up temporary file as a set. Remove official duplicate registration,
   reload the same host and rerun temporary smoke and idempotency tests.
