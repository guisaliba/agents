# Pi operating and maintenance guide

## Context

Use the repository's [`install.sh`](../install.sh) and [`pi-port`](../bin/pi-port)
for normal work. The Python launcher remains an internal, explicit-resource
entry point and a verification entry point. It starts no services itself.

The approved instructions remain in [`AGENTS.md`](AGENTS.md). The selected skill
catalog is [`skills.tsv`](skills.tsv). Local snapshot hashes, external pins, and
license attribution are in [`catalog.json`](catalog.json). The repository does
not depend on another machine's shared `~/.agents/skills` tree.

## Before/after

`pi-port` is the permanent configured entry point, not a test-only alias. Plain
`pi` currently uses the separately installed CLI and does not select this setup.
Changing the public command to `pi` remains a separate user decision.

Before, the launcher's selected skills came from this workstation's shared
installation. After, seventeen skills and their supporting files come from the
checked repository catalog, one comes from its exact private upstream checkout,
and two come from pinned Learn. This preserves all twenty selected skills.

The renderer's npm tree is locked separately because Learn's original lockfile
contains a broken author-local dependency. Manager runtime dependencies are
locked without bundling a duplicate Pi SDK. Pi supplies its own extension API
modules. Runtime scripts are not executed during npm installation.

### Daily commands

```bash
pi-port login                       # /login for both selected providers
pi-port doctor                      # no credentials printed, no inference
pi-port                             # new session, Sol main
pi-port --model openai/gpt-6-luna    # alternate approved main model
pi-port --resume                    # choose the managed main session
```

The normal wrapper selects subagents and Luna/max YSK. `/ysk off` disables new
observer checks; `/ysk on` enables them. `/agents` edits manager settings;
`/agents tree` inspects progress and provides stop/steer controls. See
[`SUBAGENTS.md`](SUBAGENTS.md) for all role assignments, limits, and costs.

Normal sessions automatically discover applicable `AGENTS.md` and `CLAUDE.md`
instruction files. Managed children use the same discovery policy. Controlled
verification uses `--no-context-files`; the dedicated verification-model mode
also disables this discovery. Extension, skill, prompt, theme, and MCP discovery
remain disabled. Six bundled roles only; no imported
OpenCode agents or separate visual-maker roles.

### Resources and state

- `launch.py`: validates binaries/backend, generates upstream memory and RTK
  extensions under a temporary private HOME, and selects explicit resources.
- `resources.py`: checks reviewed source hashes and stages approved local patches.
- `child-extensions.ts`: child-local visual and observer factories; copies the
  approved Pi instructions into the child system prompt.
- `sources.json`, `subagent-source.json`: upstream source pins and reviewed hashes.
- `subagent-config.json`: settings-only defaults for the six bundled roles.
- `configure-subagents.py`: refuses conflicting existing settings instead of
  overwriting them. It accesses no authentication.
- `renderer/`, `manager/`, `runtime/`: committed npm manifests/locks only;
  installed dependency trees remain outside this repository.
- `<private-root>/agent/sessions`: durable main and child transcripts.
- `<private-root>/agent/you-should-know`: observer feedback and request records.
- `~/.local/share/ai-memory`: the approved existing store, not a new empty store.

Visual authoring sources use session-ID paths under the OS temporary directory.
Reopening restores them while those files still exist; a reboot or temporary-file
cleanup can remove them. Published note images remain in the note's `viz/` directory.

### Handoff contract

The observer's staged entry point explicitly sets Luna/max independently of the
main model family. The first portability check caught a missing profile thinking
configuration; a separate non-GPT check caught family-based effort fallback.
Both failures and corrected status checks remain in `evidence/portable-*observer*`.

The selected generated hook checks for a pending handoff before the first normal
agent turn, not during the login-only invocation. It injects the result into
model context without a manual accept call. Session-end can create a new
**automatic successor handoff**; that is not duplicate delivery of the consumed
manual handoff.

This repository's `.ai-memory.toml` fixes `workspace=default`, `project=agents`.
The existing store rejected `guisaliba-agents` as ambiguous: it was both another
project's name and this project's canonical key. No projects or history were
renamed, moved, or deleted. The explicit marker makes native capture and static
handoff creation use the same unambiguous scope.

Handoffs are single-use and project-scoped. Launch the next live test from this
repository and send a first prompt. The next agent should answer from the
injected handoff, not call accept again or require a notes-file fallback.

## Expected behavior and verification

- Given explicit selection, then load exactly twenty skills and the selected
  extensions; discovery is not permission to load other resources.
- Given a main session with children, then keep child visual/observer state
  separate and retain assigned models/thinking.
- Given a handoff and first prompt, then inject it automatically once.
- Given a different project, then do not consume this repository's handoff.
- Given an unsupported version, missing backend, or changed source pin, then fail
  with a clear error rather than silently substitute an unreviewed component.

Focused offline checks:

```bash
./test.sh
```

Real zero-inference integration checks after installation:

```bash
ROOT="${XDG_DATA_HOME:-$HOME/.local/share}/pi-port"
export PATH="$ROOT/runtime/node/bin:$ROOT/runtime/rtk:$ROOT/packages/runtime/node_modules/.bin:$PATH"
python3 -B pi/verify-resources.py --agent-dir "$ROOT/agent" \
  --memory-binary "$ROOT/runtime/ai-memory/ai-memory" \
  --memory-endpoint http://127.0.0.1:49375 \
  --pi-binary "$ROOT/packages/runtime/node_modules/.bin/pi" \
  --subagents --ysk-model openai/gpt-6-luna --output /tmp/pi-resource-check.json
python3 -B pi/verify-handoff.py --root "$ROOT" --output /tmp/pi-handoff-check.json
python3 -B pi/verify-context.py --root "$ROOT" --output /tmp/pi-context-check.json
```

The context check verifies parent/nested instructions in both main and managed
child sessions. It also verifies child discovery of an instruction added after
the parent snapshot. Both normal and controlled modes are checked without paid
requests. Evidence: `evidence/project-context-discovery.json`.

Managed children require persistent parent sessions. Do not use `--no-session`
when delegation is needed; normal sessions already use persistent storage.
The context runner's two failed attempts remain in `evidence/project-context-*-red.json`.

The handoff check creates a synthetic fixture in its own project and uses a
synthetic provider. Do not run the `--repository-cwd` variant after saving a real
pending handoff unless you intend to start test sessions in that project.

Live verifiers for delegation, child relay, and Learn remain explicit; they use
paid/subscription requests. They refuse the shared default profile and keep
artifacts and failures. Set the private runtime PATH before running them on a
machine without global Pi/RTK. Never copy authentication to make a test pass.

Evidence:

- `evidence/portable-offline-checks.log`: focused installation/launcher checks.
- `evidence/portable-resource-discovery.json`: permanent-profile discovery.
- `evidence/portable-handoff-hook.json`: automatic single-use injection fixture.
- `evidence/portable-repository-handoff-hook.json`: same check in the real repository.
- `evidence/portable-debian-install.log`: fresh non-root Debian provisioning,
  repeat install, resource discovery, and handoff check.
- `evidence/portable-*-red.*`: retained installation/runner failures and corrections.
- `evidence/learn-workflow-live-attempt-3/`: complete synthetic teaching path.
- `evidence/subagent-integration/cost-summary.json`: six earlier live attempts,
  including failures and attributed observer requests. Catalog estimates, not bills.

The full port is ready for human login and real-work testing. Ubuntu/AArch64
installation, real Obsidian display, model quality across broad workloads, and
reliable YSK detection are not certified by these checks. Appearance changes and
replacement through a later PR remain the user's next work, not hidden tasks.
Historical Pi verification records remain under `evidence/`; they are not the
current installation instructions.
