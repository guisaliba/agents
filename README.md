# Portable Pi coding setup

## Context

This branch provides a user-local Linux installation of the selected Pi setup.
It replaces the old repository setup, not the installed OpenCode application or
shared Pi configuration. Branch `main` stays unchanged until a later PR.

The goal is a normal coding and learning workflow with explicit resources,
portable installation, and automatic cross-session handoff. Appearance changes
remain a later task.

## Before/after

Before, verification depended on a temporary authenticated profile and a
manually started memory process. After, `install.sh` provisions pinned private
runtimes, a permanent profile, a launch command, and a dedicated memory service.
Bash handles installation and launch commands. Python handles checked resource
staging and installation utilities.

```text
Repository                         User-owned installation
  install.sh  ------------------>  ~/.local/share/pi-port/
  bin/pi-port                      +-- agent/                 separate login
  pi/AGENTS.md                     +-- runtime/               Node, memory, RTK
  pi/catalog/skills/               +-- packages/              locked npm trees
  pi/patches/                      +-- memory.toml             no LLM credentials
  lib/                             +-- managed-files.json
                                   |
  ~/.local/bin/pi-port ------------+--> normal Pi session
  systemd --user --------------------> pi-port-memory.service
                                         |
                                         +--> existing ai-memory store
```

A **Pi package** distributes extensions, skills, prompt templates, or themes.
An **extension** is executable TypeScript that adds tools, commands, or lifecycle
handlers. A **skill** supplies task instructions and supporting files. There is
no separate plugin layer selected here. Learn is a collection of extensions and
skills; YSK and the subagent manager are extension packages. See the official
[packages](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/packages.md)
and [extensions](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/extensions.md)
documentation.

### Selected functionality

- Pi `1.1.0`, Node `24.21.0`, ai-memory `2.6.2`, and RTK `0.48.0`.
- The approved instructions in [`pi/AGENTS.md`](pi/AGENTS.md), including the
  user's formatting edits. The installer does not rewrite this file.
- Exactly [20 approved skills](pi/skills.tsv), including their supporting files.
  No shared skill installation is required.
- Original Learn question/quiz tools, patched Markdown logging, research
  delegation, and session-isolated SVG/Mermaid rendering.
- YSK: an independent tool-free Luna/max observer, not a managed child.
- Six bundled manager roles with the approved per-role models/thinking.
- Unmodified generated ai-memory lifecycle hooks and tools; unmodified generated
  RTK hook. The memory hook injects a pending handoff on the **first normal prompt**.
- No automatic extension, skill, prompt, theme, MCP, or context-file discovery.
  Project instruction discovery remains off under the approved explicit-resource
  contract; tell Pi to read the project's rules before working when needed.
- No additional MCP servers, Plannotator, imported OpenCode roles, or TUI changes.

Details: [Pi operating guide](pi/README.md), [subagent configuration and limits](pi/SUBAGENTS.md).

## Install

Supported installer targets: Arch Linux and Arch derivatives such as Omarchy,
Debian 12+, and Ubuntu 24.04+, on x86-64 or AArch64. Native Chromium or Google
Chrome, Python 3.11+, curl, Git, tar, xz, `sha256sum`, `rsvg-convert`, and a working
systemd user manager are required. Ubuntu snap browsers are not verified; install
an accessible native Chromium or Google Chrome first. No browser sandbox is disabled.

```bash
git clone --branch pi https://github.com/guisaliba/agents.git
cd agents
./install.sh
```

For explicit OS prerequisite installation:

```bash
./install.sh --system-packages
```

This option uses sudo and asks for normal package-manager confirmation. Without
it, the installer only checks prerequisites. On Ubuntu it does not install the
snap browser. Private Node, Pi, ai-memory, RTK, manager dependencies, and renderer
dependencies need no system-wide installation. Runtime downloads have checked
SHA-256 locks; npm uses committed lockfiles and disables install scripts.

Defaults:

| Item | Location |
| --- | --- |
| Private root | `${XDG_DATA_HOME:-~/.local/share}/pi-port` |
| Launch command | `~/.local/bin/pi-port` |
| Pi profile | `<root>/agent` |
| User unit | `${XDG_CONFIG_HOME:-~/.config}/systemd/user/pi-port-memory.service` |
| Memory endpoint | `http://127.0.0.1:49375` |
| Existing store | `~/.local/share/ai-memory` |

`PI_PORT_HOME` selects another private root during installation. The existing memory-store path is
intentionally unchanged. The launch command points to this checkout, so keep it
at a permanent path. Re-run installation after moving it. Managed-file conflicts
stop installation instead of overwriting unrelated content or later user edits.
The installer never reads, copies, or links credentials.

A **user service** is a systemd service owned by the logged-in user, without a
system-wide unit. The memory service starts with that user's systemd manager;
no lingering or boot-without-login setting is changed. It has no LLM, embeddings,
watcher, or automatic improvement scheduler configured. Its endpoint is
unauthenticated loopback; use this setup on trusted single-user machines.

Only one ai-memory server may own the store. Stop the identified previous server
before enabling this service. Never use `serve --force`. The port installation
stopped only its own temporary test server; the existing OpenCode service was
inactive and was not changed.

`--no-service` provisions files without starting/enabling the unit. It is for
container checks or staged installation, not the normal daily workflow.

## Authenticate and start

The new permanent profile is separate from all previous profiles. Authenticate
it yourself; temporary test credentials are not moved:

```bash
pi-port login
```

Inside Pi, use `/login` for `openai` and `opencode-go`, then exit. Login loads no
memory hook and therefore does not consume the pending handoff. If the command
is not on PATH, use `~/.local/bin/pi-port`; no shell configuration is modified.

```bash
pi-port doctor
```

Doctor checks versions, the approved store, and credential **readiness**, not
credential values. It returns nonzero until both providers are ready. It makes
no inference requests and does not refresh OAuth during the check.

For the next live test, start in **this repository** so the project-scoped handoff
can reach you:

```bash
cd /path/to/agents
pi-port
```

Send a first prompt, for example:

```text
Start the real Pi work test. Use the handoff already supplied in your context.
I will give you the task and report changes that I want as we work.
```

The default main model is Sol. Delegation is opportunistic and needs no approval
for each start. Children use their assigned models/thinking. YSK independently
checks at its normal schedule; silence is not proof that it found no defects.
Use `/agents tree` for progress and stop controls, `/ysk status` for observer
status, and `/settings` for normal Pi preferences.

For later work, launch from the target project's directory. Handoffs are
project-scoped, not global. The marker in this repository fixes its scope to
`default/agents`, including after a checkout is moved or renamed. It also avoids
an observed ambiguous `guisaliba-agents` selector in the existing store.

Use `pi-port --resume` and choose the **main** session to restore managed
children. Do not open an active child transcript as a separate session.

## Learning with Obsidian

Open your learning directory with `pi-port`, choose a Markdown note in your
vault, and enable `/md-log /absolute/path/to/note.md`. Then invoke
`/skill:teach` with the learning goal. Native questions and quizzes collect your
answers; researcher/coder handle authorized research and inspected visuals.
Rendered images live next to the note in `viz/`, with Markdown embeds.
Use `/md-unlog` when logging should stop.

The full teaching path passed with a synthetic learner and produced a note and
PNG embed. Obsidian itself was not launched or inspected. Your real vault,
learning needs, and Obsidian display remain part of the next live work test.

## Expected behavior and checks

- Given a clean supported machine, then install without shared skills, global
  npm packages, copied credentials, or a temporary source/profile path.
- Given a repeat installation, then retain authentication and refuse foreign
  managed-file conflicts.
- Given a pending handoff, then the first normal prompt receives it automatically;
  another session does not receive that same handoff again.
- Given failed prerequisites, credentials, or memory health, then return a clear
  failure rather than start an incomplete normal session.
- Given the old application remains installed, then leave it unchanged until
  the user completes replacement through a later PR.

```bash
./test.sh
# Optional real Debian provisioning/discovery/handoff check:
./pi/test-linux-install.sh
```

Current installation evidence:

- This Omarchy x86-64 host: provisioned, repeat-installed, user service active,
  exact resource discovery passed, and real-repository handoff injection passed.
- Fresh pinned Debian 12 container: non-root provisioned, repeat-installed,
  exact resource discovery passed, and handoff injection passed. No host home,
  credentials, or memory store was mounted. The provider was synthetic.
- Ubuntu and AArch64 paths are implemented but not live-certified here.
- Real six-role delegation and Learn execution are retained from the earlier
  authenticated tests. No new permanent-profile inference was attempted before
  human login.

Evidence and failed runner attempts remain under [`pi/evidence/`](pi/evidence/).
The handoff and container tests use a synthetic provider and make no paid model
requests. They prove hook integration, not model quality. Reliable YSK detection
of the synthetic billing inconsistency remains unverified.

## Maintenance and removal

Upstream pins/hashes are in `pi/sources.json`, `pi/subagent-source.json`, and
`pi/catalog.json`. Local integration patches are reviewed maintenance work, not
upstream releases. Re-run focused checks after changing them. Do not use an
unreviewed `pi update --all` against this pinned setup.

Third-party skill licenses and attribution are in `pi/catalog/licenses/` and
`pi/catalog.json`; root `LICENSE` does not replace their terms. The unlicensed
logging skill is fetched into the private profile at an exact commit, not
redistributed in this repository.

To stop daily memory service use:

```bash
systemctl --user disable --now pi-port-memory.service
```

Removal is manual. Preserve `<root>/agent` if it contains authentication or
sessions, and always preserve the existing memory store. No uninstall command
silently deletes either. The old repository code and installation documentation
have been removed from this branch; prior Pi test history remains as evidence.
