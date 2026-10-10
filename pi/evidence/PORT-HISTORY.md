# Pi port: decisions and verification

## Context

This first port adds selected Pi components without changing the working
OpenCode installation, shared skills, instructions, services, or memory data.
The long-term choice between two harnesses and Pi alone remains open.

Approved so far:

- Reuse the store at `~/.local/share/ai-memory`.
- Run a temporary local ai-memory process on a free loopback port.
- Use a checksum-verified 2.6.2 release binary in a private temporary directory
  for verification. Do not upgrade the shared installation.
- Use the unmodified upstream-generated Pi extension for memory tools,
  automatic lifecycle capture, and session-aware project routing.
- Test the upstream-generated Pi RTK extension using the existing 0.48.0 CLI,
  without a shared install or CLI upgrade.
- Use a separate launcher with explicit resources and automatic discovery
  disabled.
- Capture projects opened through this launcher without requiring a marker.
  Generate its memory extension with upstream `denylist` capture; existing
  exclusions still apply. Do not change OpenCode's capture policy.

ai-memory and RTK verification passed. The user supplied and approved the
separate Pi instruction file, [`AGENTS.md`](AGENTS.md), including its revised
memory paragraph. It is saved in this repository, not installed into the Pi
agent directory. Shared instructions remain unchanged. Select remaining
components and new additions separately. Do not import OpenCode subagent
settings, models, instructions, or delegation.

## Current manager and Learn integration

The selected subagent manager, six approved role assignments, Learn child
rendering, and YSK child-note relay now have live evidence. See
[`SUBAGENTS.md`](SUBAGENTS.md) for setup, controls, model configuration, costs,
retained failures, and the complete tested teaching path.

Use `--subagents` to select this integration. YSK remains separately selected
with `--ysk-model`. The later sections of this file record earlier port stages;
statements that delegation or child relay were deferred describe those stages,
not the current integration. Permanent daily memory-process setup and later MCP
selection remain open. Shared configuration and OpenCode remain unchanged.

## Before/after

Before: `apply.sh` and `test.sh` describe OpenCode installation and host checks.
They are evidence, not the Pi design. Neither script has been run for this port.

After: the full Pi setup is not complete. The launcher explicitly loads memory,
RTK, four original Pi Learn extensions, 20 selected skills, and the approved Pi
instructions. Learn's logger uses a reviewed local patch. YSK is loaded only
with an explicit `--ysk-model` choice. Automatic resource discovery and other
MCP servers remain disabled. Launcher tests prove capture without a marker.
Shared configuration is not installed or changed by the launcher.

## Verified behavior

Initial checks on this host:

- Pi 1.1.0 exposes 54 shared skill commands by default; `--no-skills` exposes
  none. Discovery is not approval.
- Pi accepts `openai/gpt-6.1-sol` and `openai/gpt-6-luna` through RPC model
  selection. Both also made successful real memory-tool calls in the 2.6.2
  verification run. This does not implement planning/building roles.
- Pi has no built-in planning/building roles or plan mode. No alternative or
  role implementation has been selected.
- The local ai-memory service is disabled and inactive. OpenCode owns the
  default ai-memory port, `127.0.0.1:49374`. Neither service was changed.
- The approved temporary ai-memory process identifies the selected store.
  It uses a separate temporary configuration, no inherited credentials, no LLM
  provider, no embeddings, no watcher, and no auto-improvement scheduler.
  It started with 2.6.0 and was replaced with the approved private 2.6.2 binary.
  The replacement retained every pre-existing page, session, and observation ID.
- The selected database had zero pages, sessions, and observations before
  startup. Their identifier sets were unchanged after startup. This is not
  evidence that prior OpenCode history is present in that store.
- One real Pi session using `openai/gpt-6.1-sol` successfully called the
  extension's `memory_status` tool with no explicit scope. Its response named
  the test workspace and project.
- That session produced all six expected observation kinds: session-start,
  user-prompt, pre-tool-use, post-tool-use, stop, and session-end. Its stored
  session is marked ended.

The eight functional checks passed three times, each time through six real Pi
sessions. The retained final run uses normal startup timing, with no artificial
delay. A later isolation check found a failure, described below; these runs
must not be presented as fully successful verification:

- Concurrent live sessions in two projects resolved unscoped `memory_status`
  calls to their own project, including A again after B's call.
- An unscoped `memory_write_page` wrote the synthetic tool fact in project A.
- A fresh project-A session retrieved the fact without resuming old context.
- A fresh project-B session answered an ordinary question about project A's
  TypeScript tool. It chose global `memory_query` searches and read the source
  page with explicit scope. The prompt did not specify tool calls or the answer.
- A fresh project-A session received a synthetic profile entry through the
  upstream custom-message injection path and repeated its label without
  querying memory. Only this run's unique profile fixture was then deleted.
- Every stored session ended, had the required lifecycle observation kinds,
  and kept its observations in its own project.
- The test retained every record ID present before the run.

**Profile delivery is verified; automatic preference harvesting is not.**
The profile fixture was written directly through Pi's memory tool. Do not
present this check as proof of automatic learning or universal recall.

### Test-isolation failure

The initial runner used the normal Pi agent directory. Its RPC
`set_auto_retry` call persists the retry setting in that directory. Earlier
RPC model-selection probes also persist defaults. The shared Pi settings file
was modified; claiming every shared configuration was unchanged was incorrect.
OpenCode's binary, RTK plugin, and listener remain unchanged.

Evidence: `~/.pi/agent/settings.json` modification time and the official
[Pi session implementation](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/src/core/agent-session.ts)
(`setAutoRetryEnabled` and `setModel`). No secret values were inspected.
The prior Pi settings were not backed up, so do not guess their original values
or restore them without the user's approval.

The runner now requires a separate `--agent-dir`, rejects the normal Pi agent
directory, and checks shared-settings metadata before and after the run.
Credentials supplied through provider environment variables can be inherited
by the separate directory without another login. Alternatively, use Pi's
`/login` in that directory; do not copy or symlink shared credentials. The
corrected runner has now passed a live run with nine checks across six Pi
sessions. Shared Pi settings metadata was unchanged in that run. This prevents
further test changes; it does not restore the earlier unintended changes.

The user approved `opencode-go/deepseek-v4.1-flash` as a verification model,
not as a replacement for either requested primary model. A direct request from
the separate directory initially failed with `No API key found for opencode-go.`
The user then completed `/login` in the separate directory. Pi reported API-key
authentication ready, and all nine checks passed using that provider and model.
No credential value was read or displayed by the assistant. Authentication by
API key does not by itself mean the key is supplied through an environment
variable. Historical failure evidence is retained in
[`evidence/opencode-go-authentication.json`](evidence/opencode-go-authentication.json).

RTK command rewriting and output reduction passed through real Pi tool calls,
as described below. The Pi instruction file is approved and saved. The launcher
now loads it through a supported Pi CLI option, verified in print and interactive
sessions. Both requested primary models have now passed this launch path in
print and interactive sessions. A durable daily memory-process setup remains
pending; the current server and 2.6.2 binary were approved for tests.

Current sanitized passing evidence:
[`evidence/ai-memory-isolated-deepseek.json`](evidence/ai-memory-isolated-deepseek.json).
The earlier functional run and its isolation failure remain in
[`evidence/ai-memory-2.6.2.json`](evidence/ai-memory-2.6.2.json).
The reproducible runner is [`verify-ai-memory.py`](verify-ai-memory.py). It keeps
only test metadata and tool-call arguments in the artifact, not raw tool results
or transcripts. Synthetic project pages and captured sessions remain in the
approved store as evidence; the temporary profile page is removed.

The private pre-start database backup remains outside Git under
`/tmp/pi-port-docs/`. Do not commit or publish it.

## RTK verification

[`verify-rtk.py`](verify-rtk.py) passed ten checks through nine real Pi sessions.
It generates the extension with the installed RTK CLI inside a private fixture.
The generated file matched the published
[RTK v0.48.0 Pi extension](https://github.com/rtk-ai/rtk/blob/v0.48.0/hooks/pi/rtk.ts)
byte-for-byte (commit `fde0a8f185945556f51718de0f4c430bb62b3df6`, SHA-256
`48f07e4fd8e38b350cae84fe0116d2bc29932d535e333a307cb9e477f5272de6`).
No generated integration payload is vendored in this repository.

Verified behavior:

- Pi's model requested `git log -20` through `bash`. The upstream extension
  invoked `rtk rewrite`, and the executed command was `rtk git log -20`.
- Model-visible output fell from 3,299 bytes to 1,280 bytes: 61.2% reduction.
  All twenty synthetic commit subjects remained present.
- `RTK_DISABLED=1` kept the original command and full output.
- An unsupported `printf` command ran unchanged.
- An intentionally invalid Git command remained a failed Pi tool result.
- Controlled rewrite failure, a timeout with partial helper output, a missing
  CLI result, and an old-version result preserved original command execution.
  These are simulated helper conditions; the installed binary was not removed
  or changed.
- Both approved upstream extensions worked together: Pi ran the rewritten
  command, called `memory_status` for its own project, and stored an ended
  session with both tool results captured.
- Shared Pi settings metadata was unchanged.

The test-only command gate blocks unexpected shell commands. An audit wrapper
records RTK arguments and delegates actual successful rewriting/execution to
the installed binary. RTK configuration, metrics, and Git configuration are
isolated. This instrumentation is not a custom runtime integration or a general
security boundary. RTK itself is rewrite-only and does not authorize commands.

Sanitized evidence: [`evidence/rtk-0.48.0.json`](evidence/rtk-0.48.0.json). Outputs
in this artifact come from synthetic fixtures only. Reproduce against the
approved temporary memory server and separately authenticated Pi directory:

```bash
python3 -B pi/verify-rtk.py \
  --agent-dir /path/to/private/pi-test-agent \
  --model opencode-go/deepseek-v4.1-flash \
  --memory-binary /path/to/private/ai-memory-2.6.2 \
  --memory-endpoint http://127.0.0.1:PORT \
  --output /path/to/private/rtk-verification.json
```

The working OpenCode RTK plugin is unchanged. Neither `apply.sh` nor `test.sh`
was run. The temporary ai-memory process still uses a separate loopback port;
this does not configure the final daily launch path.

## Explicit Pi launcher

[`launch.py`](launch.py) starts Pi from the caller's working directory. It uses
Python's standard library and the existing Pi, RTK, and approved ai-memory
executables. It does not install packages, write shared settings, create project
markers, copy credentials, or start a service.

Before: integration tests assembled their own Pi commands. After: one launcher
generates the unmodified memory and RTK extensions, stages Learn's patched
logger, and loads the selected sources and skills explicitly. Generated files
are removed after Pi exits. Pinned upstream packages are installed separately
with Pi's supported package command; the launcher does not install them.

Requirements and limits:

- Supply an existing local ai-memory 2.6.2 endpoint serving the approved store
  at `~/.local/share/ai-memory`. Other hosts, redirects, credentials in URLs,
  extra paths, and a different store are refused.
- Supply the approved ai-memory executable. The launcher checks the verified
  versions: Pi 1.1.0, ai-memory 2.6.2, and RTK 0.48.0. It does not upgrade them.
- Supply the Pi agent directory explicitly and authenticate through Pi's
  supported mechanism. Normal Pi preferences in that directory can still
  apply; resource discovery is disabled. Directories with `SYSTEM.md`,
  `APPEND_SYSTEM.md`, or `models.json` are refused because those can introduce
  unapproved prompt or model overrides.
- Select `--model openai/gpt-6.1-sol` or `--model openai/gpt-6-luna`. These are
  explicit model choices, not planning/building roles or an automatic router.
- `--verification-model opencode-go/deepseek-v4.1-flash` is for approved isolated
  tests only. It cannot use the normal shared agent directory or resume a
  previous session. It is not a primary-model replacement.
- Install the pinned sources using the separate resource profile described
  below. Missing or changed reviewed files stop the launch.
- The selected tools are `read`, `bash`, `edit`, `write`, `memory_*`,
  `ask_user_question`, and `quiz`. The 20 approved, unchanged skills in
  [`skills.tsv`](skills.tsv) now load explicitly. Loading does not verify all
  workflows or authorize additional dependencies.
- Optional `--ysk-model openai/gpt-6-luna` or `--ysk-model openai/gpt-6.1-sol`
  loads the original YSK extension and sets its supported `YSK_MODEL` override.
  This is an explicit observer-model choice, not a plan/build router. Without
  this argument, YSK is not loaded, even if its package is installed.
- `--no-context-files` also disables repository `AGENTS.md`/`CLAUDE.md` discovery.
  Only the reviewed Pi instruction file is appended automatically. This is the
  initial explicit-resource policy, not a decision to delete project rules.
- Session files go into the chosen agent directory, even if project settings
  declare another session directory. `--continue` resumes the current project's
  session; `--no-session` uses an in-memory Pi session.
- The generated memory extension uses `denylist` capture and `repo-root`
  routing. No marker is required; upstream exclusions still apply. The
  generator uses a private HOME/config and never receives `--apply`, so this
  does not change the shared capture mode or OpenCode integration.
- An inherited external capture owner is refused. A parent harness's managed
  run ID is not forwarded; Pi retains its own lifecycle identity.

Run from the project you want to work on, using approved real paths:

```bash
python3 -B /path/to/agents/pi/launch.py \
  --agent-dir /path/to/authenticated/pi-agent \
  --memory-binary /path/to/approved/ai-memory-2.6.2 \
  --memory-endpoint http://127.0.0.1:PORT \
  --model openai/gpt-6-luna
```

Add `--print "message"` for a single text response, `--mode json --print
"message"` for JSON events, or `--mode rpc` for RPC. Resource flags are not
forwarded: unselected extension, skill, prompt, and model overrides are rejected.

**Initial verification:** ten checks passed through real print and interactive Pi
sessions, plus twelve focused unit tests. Both sessions used the already
approved isolated DeepSeek test model. The tests proved exact instruction
content reached Pi's system prompt, marker-free capture ended both sessions,
both tool calls were stored, and actual RTK rewriting reduced model-visible
output from 3,279 to 1,260 bytes without losing any synthetic commit subject.
The interactive check exited normally with Pi's documented Ctrl+D action.
Unselected fixture resources did not load, session-directory overrides did not
apply, generated resources were cleaned up, and shared configuration metadata
remained unchanged.

Evidence: [`evidence/launcher.json`](evidence/launcher.json). Reproduce:

```bash
python3 -B pi/test-launch.py -v
python3 -B pi/verify-launch.py \
  --agent-dir /path/to/private/pi-test-agent \
  --memory-binary /path/to/private/ai-memory-2.6.2 \
  --memory-endpoint http://127.0.0.1:PORT \
  --output /path/to/private/launch-verification.json
```

**Primary-model verification:** the user authenticated OpenAI in the same
isolated directory through Pi. A credential-status check reported `ready`
with `authType: oauth`; no credential values were read, printed, or copied.
Both `openai/gpt-6.1-sol` and `openai/gpt-6-luna` then passed eleven checks
through the launcher, each in a print and an interactive session: twenty-two
checks across four real Pi sessions. Assertions checked both the provider/model
in actual assistant responses and the model active before each interactive
turn, so this is not merely a model-selection or authentication-status check.
Both models used memory tools, produced reduced RTK output, and stored ended
marker-free sessions with both tool results. Shared configuration metadata
remained unchanged.

Evidence: [`evidence/launcher-primary-models.json`](evidence/launcher-primary-models.json).
Repeat `verify-launch.py` above with `--model openai/gpt-6.1-sol`, then with
`--model openai/gpt-6-luna`, using separate output files. The default remains
the approved DeepSeek test model for existing reproduction commands. Primary
verification does not implement planning/building roles or an automatic router.

**Not complete:** the 20 skills now load, but some workflows still require
additional tools or the deferred sub-agent system. Additional MCP servers and
further Pi-native extensions remain pending. The temporary memory process and
private 2.6.2 binary are test infrastructure, not a durable daily installation.
No permanent service or shared upgrade is approved.

Official Pi references: [CLI resource and prompt options](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/cli.md),
[configuration](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/configuration.md),
[keybindings](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/keybindings.md),
and [security limits](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/security.md).
Resource selection is not a sandbox or a permission gate.

## Selected skills: loading is not workflow execution

The user first approved 18 unchanged skills, then added original Learn's
`teach` and `visualize`: 20 in [`skills.tsv`](skills.tsv). The root inventory and
shared skill files remain unchanged. Do not adapt `grilling` merely to reconcile
its instructions with this session's older instructions.

The first RPC discovery check loaded the original 18 explicit paths without
model requests. Its historical evidence remains in
[`evidence/selected-skill-discovery.json`](evidence/selected-skill-discovery.json).
The current launcher check loads exactly all 20 without automatic discovery or
model requests: [`evidence/learn-resources.json`](evidence/learn-resources.json).
Both checks retained shared-settings metadata. Loading is not workflow execution.

Inspection found these workflow limits, without changing skill content:

- `grill-with-docs` explicitly calls a `Skill` tool; Pi uses file reading and
  `/skill:name` commands instead. `tdd` has a similar conditional instruction.
  The relevant sibling skills were selected, but that invocation path is not
  yet verified.
- `grilling` and codebase-design's `DESIGN-IT-TWICE.md` require sub-agent
  exploration. The sub-agent extension is deferred and has not been selected.
  `improve` has a
  documented direct-audit fallback, but its executor variant requires subagents.
- Plannotator is excluded from the Pi port: its plugin, all its skills, and
  visual-explainer dependencies are not selected. The user removed both
  `plannotator-review` (catalog ID 27) and `plannotator` (ID 52), after removing
  `plannotator-visual-explainer` (ID 32). Keep shared OpenCode installations and
  shared skill files unchanged.
- The ai-memory maintenance tools can require server-side processing. The
  verification server still has no LLM provider and no scheduler; selecting
  instructions does not change that configuration.

The following Plannotator findings are historical research, not installation
instructions: the product is excluded from Pi. Product installation and Pi
skill selection are separate. Current upstream Plannotator's Pi extension bundles the core `plannotator` reference, offered
only when that exact skill is not already loaded. It does not bundle every
extra skill. Its full CLI installer also installs core skills; extras are
optional. The old root inventory's review/annotate/last source points to
`apps/skills/extra`, but current upstream places them under `apps/skills/core`.
The Pi-specific inventory uses the checked current source for selected skills;
the working OpenCode inventory is not rewritten.

ai-memory installs hooks, tools, and skills through separate commands.
`install-instructions` normally includes managed skills unless `--no-skills`
is set; `install-skills` installs the managed set in one operation. Inventory
rows describe the available instructions, not a requirement for separate
installation per skill. The original `apply.sh` explicitly installs routing
with `--no-skills`, then calls `install-skills` once (`apply.sh:2241–2248`).
Neither command is being applied to shared files by this inspection.

Official sources: [Plannotator Pi extension](https://github.com/backnotprop/plannotator/tree/main/apps/pi-extension),
[core skills](https://github.com/backnotprop/plannotator/tree/main/apps/skills/core),
[extra skills](https://github.com/backnotprop/plannotator/tree/main/apps/skills/extra),
[ai-memory skill installer](https://github.com/akitaonrails/ai-memory/blob/v2.6.2/crates/ai-memory-cli/src/commands/install_skills.rs),
and [Cloudflare discovery skill](https://github.com/cloudflare/skills/tree/main/skills/cloudflare).

## Original Pi Learn: configuration and logger stage

### Context

Use [amosblomqvist/learn](https://github.com/amosblomqvist/learn), not the
OpenCode implementation. The pin is `7cfd8942f82ab9476e63572387e1fe9bcea5082c`.
The user approved its full workflow, two skills, integrations, and three agent
definitions. This stage configures those sources before the deferred sub-agent
system; it does not claim full research or visual execution.

A **resource profile** is a separate Pi agent directory used only for installed
packages, not authentication. Keep it under the chosen authenticated directory
as `port-resources`. This prevents ordinary Pi startup in the authenticated
profile from loading the unpatched upstream logger. Do not authenticate the
resource profile or copy credentials into it.

Use the supported Pi package commands, without `--local`:

```bash
mkdir -p /path/to/authenticated/pi-agent/port-resources
chmod 700 /path/to/authenticated/pi-agent/port-resources
PI_CODING_AGENT_DIR=/path/to/authenticated/pi-agent/port-resources \
  pi install git:github.com/amosblomqvist/learn@7cfd8942f82ab9476e63572387e1fe9bcea5082c
PI_CODING_AGENT_DIR=/path/to/authenticated/pi-agent/port-resources \
  pi install git:github.com/aliceisjustplaying/pi-you-should-know@4ffe3daec322de069bd15e174f23b6d4a5c45419
```

[`sources.json`](sources.json) records the reviewed file hashes.
[`resources.py`](resources.py) verifies those files and stages only the logger
patch. It does not edit either upstream checkout. Other Learn files remain
unchanged, including the skills and agent definitions. Pi 1.1.0 loaded their
legacy module aliases without a compatibility rewrite.

### Before/after

The pinned logger replaced the entire note on linking:

```typescript
fs.writeFileSync(logFile, blocks.join("\n\n") + "\n\n", "utf-8");
```

The local [`patches/learn-md-log.patch`](patches/learn-md-log.patch) gives each
session an **owned section**, the text between markers with that session's ID.
It retains text outside the section, replaces only that section on relinking,
and appends live events inside it. The complete updated file is staged before
replacement:

```typescript
fs.writeFileSync(candidate, updated, { encoding: "utf-8", mode });
fs.chmodSync(candidate, mode);
fs.renameSync(candidate, target);
```

The explicit `chmod` retains existing permission bits despite the process
`umask`, the permission mask applied when a process creates a file. Linking
validates even when no lesson history exists. Damaged markers or insufficient
permissions produce an error without a false success notification. The patch
has not been published upstream.

### Expected behavior and evidence

[`verify-learn.py`](verify-learn.py) passed 12 real Pi checks using synthetic
notes and a real Luna response. It never used private notes. Retained artifacts:

- [`evidence/learn-overwrite-red.json`](evidence/learn-overwrite-red.json): the
  original logger removed existing content.
- [`evidence/learn-umask-red.json`](evidence/learn-umask-red.json): the first
  local patch changed `0644` to `0600` under a restrictive `umask`.
- [`evidence/learn-first-link-red.json`](evidence/learn-first-link-red.json): the
  first local patch reported success for an unwritable note before a lesson.
- [`evidence/learn-encoding-red.json`](evidence/learn-encoding-red.json): the
  first local patch changed bytes in a note with invalid UTF-8.
- [`evidence/learn-md-log.json`](evidence/learn-md-log.json): the final 12 checks
  passed. Before/after files are in `evidence/learn-md-log-fixtures/`.
- [`evidence/learn-resources.json`](evidence/learn-resources.json): the real
  launcher loaded exactly 20 skills, activated question and quiz tools, and
  did not activate a sub-agent or child visual tool.
- [`evidence/launcher-with-learn.json`](evidence/launcher-with-learn.json): 11
  launcher checks with Learn loaded, including real print and terminal use,
  RTK rewriting, memory capture, and shared-configuration preservation.

Given an existing note, then its outside text remains unchanged. Given repeated
linking, then the history is not duplicated. Given live output, then only the
session section changes. Given a new session, then it does not retain the old
note link. Given bad markers, invalid UTF-8, or an unwritable note, then report failure
and retain the note's bytes. Given an existing mode, then retain its permission bits.

Reproduce the logger check with a private staged path:

```bash
PYTHONPATH=pi python3 -B - <<'PY'
from pathlib import Path
from resources import patched_logger
stage = Path('/path/to/private/logger-stage')
stage.mkdir(mode=0o700, parents=True, exist_ok=True)
print(patched_logger(Path('/path/to/authenticated/pi-agent'), stage))
PY
python3 -B pi/verify-learn.py \
  --agent-dir /path/to/private/pi-test-agent \
  --extension /path/to/private/logger-stage/extensions/md-log.ts \
  --output /path/to/private/unique-learn-run.json
```

The entry command is `/skill:teach`, not `/learn`. Question and quiz tools are
loaded and active; their complete interactive teaching workflow was not run in
this logger-focused stage. The visual registration hook is loaded but is a
no-op without `__pi_interactive_subagents.registerToolExtension`. The researcher
still needs `web_search`, `web_fetch`, and `safe_bash`. Agent-defined GLM and
Sonnet models are not selected or enabled. Renderer dependencies, Linux browser
configuration, and upstream's `--no-sandbox` choice remain unresolved and are
not installed or executed. These are deferred checks, not completed features.

Official Node references: [file mode and chmod](https://nodejs.org/docs/latest-v25.x/api/fs.html#fschmodsyncpath-mode)
and [rename](https://nodejs.org/docs/latest-v25.x/api/fs.html#fsrenamesyncoldpath-newpath).

Replacement retains tested content and permission bits. It does not claim
preservation of ownership, ACLs, extended attributes, hard links, or concurrent
editor writes. No lock coordinates external editors in this stage.

The upstream repository declares no license. The user reports the author's
permission for the public video; that statement is not a verified license grant.
The original source remains outside this repository.

## Pi-native extension: You Should Know

### Context

[aliceisjustplaying/pi-you-should-know](https://github.com/aliceisjustplaying/pi-you-should-know)
is pinned at `4ffe3daec322de069bd15e174f23b6d4a5c45419`. This is a Pi-native
addition, not a migration of OpenCode extensions. Its source is unchanged.
The package declares `UNLICENSED`; do not claim a redistribution license.
The package installation added no library dependencies.

An **observer** is a tool-free side-model request which checks the current
conversation for useful notes. This extension makes those requests directly;
it does not need an external sub-agent extension for observation. Its separate
child-to-parent relay uses sub-agent activity and artifact files. Only protocol
fixtures tested that relay; no sub-agent system has been installed.

### Before/after

Before: YSK was not installed or selected. After: it is installed in the private
resource profile and can be explicitly loaded by the launcher:

```bash
python3 -B /path/to/agents/pi/launch.py \
  --agent-dir /path/to/authenticated/pi-agent \
  --memory-binary /path/to/approved/ai-memory-2.6.2 \
  --memory-endpoint http://127.0.0.1:PORT \
  --model openai/gpt-6-luna \
  --ysk-model openai/gpt-6-luna
```

The two model choices are explicit and may differ, but both must be one of the
two approved primary IDs. `--ysk-model` sets the upstream `YSK_MODEL` override;
it does not add a local model router or modify the extension. YSK is absent
without that option. Its `/ysk on`, `/ysk off`, `/ysk status`, note commands,
feedback, and stored preferences remain upstream behavior.

Observation adds model requests and sends conversation context to the selected
provider. The live checks used upstream's GPT-family `high` thinking setting.
Each check adds token usage; this stage did not verify provider billing.
Both live test observers returned `learn: none`, so
neither test claims a real model-generated alert was displayed.

### Expected behavior and evidence

- Given seven controlled read turns, then step 6 schedules a real observer
  request on the exact selected model.
- Given `learn: none`, then finish without adding a note.
- Given the upstream `/ysk test` sample, then RPC delivers the note and accepts
  answer commands without inference.
- Given that sample in a terminal, then display the widget, selection menu, and
  explanation; Enter closes the explanation and Ctrl+D exits normally.
- Given no sub-agent extension, then observation still works. Real delegated
  child-to-parent note delivery remains deferred.

[`verify-ysk.py`](verify-ysk.py) passed four checks with each real primary model,
including terminal sample interaction without model requests:
[`evidence/ysk-live-luna.json`](evidence/ysk-live-luna.json) and
[`evidence/ysk-live-sol.json`](evidence/ysk-live-sol.json).
[`verify-resources.py`](verify-resources.py) also verified exact skill/tool
selection, the configured observer model, and sample RPC note controls:
[`evidence/ysk-resources.json`](evidence/ysk-resources.json).

The unchanged upstream suite passed **16 of 17**, not all tests. `GPT default`
failed with `ECONNRESET`, and its focused repeat failed too. Retain the failure:
[`evidence/ysk-upstream-tests.tap`](evidence/ysk-upstream-tests.tap) and
[`evidence/ysk-focused-default.tap`](evidence/ysk-focused-default.tap).
Those detection/routing tests run real Pi with local protocol responses, not
live provider responses. The default-provider fixture failure remains
unresolved; the explicit approved model paths passed separate live checks.
No upstream test was removed or weakened.

Reproduce the live check with an approved memory server:

```bash
python3 -B pi/verify-ysk.py \
  --agent-dir /path/to/private/pi-test-agent \
  --memory-binary /path/to/private/ai-memory-2.6.2 \
  --memory-endpoint http://127.0.0.1:PORT \
  --model openai/gpt-6-luna \
  --output /path/to/private/ysk-live.json
```

Use Sol in a separate run to verify the other model. All retained live artifacts
contain only controlled test metadata, not credentials or raw provider errors.
Shared-settings metadata was unchanged. The next stage selects a sub-agent
system and connects the deferred interfaces; it must not import OpenCode's
architecture.

Official Pi references: [packages and resource filters](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/packages.md),
[extension APIs](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/extensions.md),
and [RPC commands](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/rpc-commands.md).

## YSK detection-quality pilot

### Context

The user approved 12 synthetic conversations, three repetitions per model, and
parallel execution: 72 observer requests. The requested comparison was Luna
at its highest supported effort and Sol at `low`. Pi reported Luna `max`; all
36 live Luna requests transmitted `max`, and all 36 live Sol requests
transmitted `low`. Both used tool choice `none` and returned successful
responses. No production setting or YSK feedback file was changed.

### Before/after

The earlier live checks only tested successful inference returning `learn:
none`. This pilot used the pinned, unchanged upstream detection prompt with
fixed synthetic conversation messages. [`ysk-corpus.json`](ysk-corpus.json)
contains the original expected findings, defined before requests.
[`benchmark-ysk.py`](benchmark-ysk.py) ran six concurrent jobs through the
explicit test-only [`ysk-benchmark-driver.ts`](ysk-benchmark-driver.ts).

The driver uses Pi's supported `ctx.modelRegistry.streamSimple()` interface
and the upstream tool-free side-call structure. It does not load the production
YSK extension, change its configuration, or test scheduling, note delivery,
feedback, or cache alignment. There were no paid main-agent conversation calls.
The short synthetic coding system prompt is shared by both models; this is not
an evaluation of long, real project histories.

### Expected behavior and results

Given an important unreported regression, then the observer should identify it
with correct evidence. Given a verified harmless change, then it should remain
silent. Both models detected all six intended important findings in every
repetition: 18/18 each, with matching file evidence. Neither missed an intended
important finding in this set.

However, the intended silence controls were not clean. This is a defect in the
benchmark, not proof that the models produced false warnings:

- C02 also changes the error-handling path; the surrounding handler is absent.
- C04 places index creation in lookup SQL without migration context.
- C06 does not enforce permissions on an existing file. The Node documentation
  states that the `mode` option affects only newly created files:
  [writeFile](https://nodejs.org/docs/latest-v25.x/api/fs.html#fswritefilefile-data-options-callback).
- C08 claims a successful request without a recorded test result and changes
  the client-wide log level.
- C10 creates a named index in cleanup SQL without a repeat-execution guard.
- C12 has a constant cache key and claims a passing pipeline without a recorded
  run; installation order and release dependencies are absent.

All six control cases are marked inconclusive. Their original labels and
responses remain unchanged. Do not report a false-positive rate from them.

| Measure | Luna `max` | Sol `low` |
|---|---:|---:|
| Successful requests | 36/36 | 36/36 |
| Intended important findings | 18/18 | 18/18 |
| Notes on intended controls, not validated false alarms | 14/18 | 17/18 |
| Catalog cost estimate for 36 requests | $0.0348042 | $0.599072 |
| Median request time with six concurrent jobs | 13.37 s | 7.05 s |

Sol's recorded cost estimate was 17.21 times Luna's for this pilot. These are
catalog estimates, not bills or guaranteed production costs. Repetitions do
not make the six distinct positive examples a broad quality evaluation.
That original pilot did not contain enough valid negative-case evidence to
select a production model on overall detection quality. The approved corrected
control run below supplies additional evidence.

Artifacts in [`evidence/ysk-quality-pilot/graded-summary.json`](evidence/ysk-quality-pilot/graded-summary.json):
`protocol.json` records the pre-run hashes; `results.json` retains all 72
responses and wire settings; `blind-review.md` withholds model identities;
`blind-grades.json` records the review; `blind-key.json` maps review labels.
The assistant reviewed outputs before opening the label key; this was not an
independent external judge. Shared-settings and YSK feedback metadata remained
unchanged. The upstream default-transport failure remains unresolved.

Reproduce in a separately authenticated test directory and a new output folder:

```bash
python3 -B pi/benchmark-ysk.py \
  --agent-dir /path/to/private/pi-test-agent \
  --output-dir /path/to/private/new-quality-pilot \
  --workers 6
```

The original pilot remains unchanged. The user then approved 36 additional
parallel requests using six corrected silence controls.

### Corrected control run

**Context:** [`ysk-controls.json`](ysk-controls.json) adds missing inspection
context, separates migrations from recurring queries, preserves existing error
handling, and provides fixed synthetic verification receipts. These receipts
are replay inputs, not real application tests executed by the benchmark.

**Before/after:** the first controls contained other valid concerns. The new
controls establish safe behavior without revealing their expected labels to
the observer. [`benchmark-ysk.py`](benchmark-ysk.py) supports `--corpus controls`;
the upstream prompt, side-call driver, and model reasoning choices are unchanged.
Model-blind review artifacts now include the inspection context and receipts.

**Expected behavior:** given a safe, verified change in the replay, then remain
silent. All 36 real observer requests returned `learn: none`: 18/18 for Luna
`max` and 18/18 for Sol `low`. The six-worker run took 40.17 seconds. Wire
settings and tool choice `none` were checked for every response.

Combining only the original important-finding cases with these corrected
controls gives each model 18/18 detections and 18/18 correct silence results:
no observed missed important findings or false alerts on these scenarios.
The invalid original controls are excluded, not deleted or relabeled.

| Measure | Luna `max` | Sol `low` |
|---|---:|---:|
| Correct silence in new requests | 18/18 | 18/18 |
| New-run catalog cost estimate | $0.0151437 | $0.2645284 |
| New-run median request time | 6.673 s | 2.847 s |
| Cost estimate for valid positive + corrected control cases | $0.03070876 | $0.5635344 |

On the valid comparison cases, Sol's estimate was 18.35 times Luna's. This
supported Luna `max` under the user's stated cost/quality preference. The user
then selected Luna `max` as the YSK observer; this choice is settled. It does not establish general equivalence: there are
only twelve short synthetic scenarios, each repeated three times, and no long
real-project histories. Sol was faster in these concurrent runs.

Evidence: [`evidence/ysk-quality-controls/graded-summary.json`](evidence/ysk-quality-controls/graded-summary.json),
with all responses, pre-run hashes, model-blind review, and grades in the same
folder. Normal shared-settings and YSK feedback metadata remained unchanged.
The comparison itself changed no production observer choice or default thinking
level. After the user's decision, [`ysk-config.json`](ysk-config.json) records
Luna/max using upstream's supported GPT-family configuration. The same non-secret
configuration was placed in the private test profile's `you-should-know/config.json`,
which did not previously exist. It does not change the main model. Continue to
pass `--ysk-model openai/gpt-6-luna` to enable observation. Model overrides alone
do not change thinking: the family configuration sets `max`.

A zero-request real Pi status check verified Luna/max as observer while Sol
remained the main model:
[`selected-observer.json`](evidence/ysk-transport-diagnosis/selected-observer.json).

### Bounded transport diagnosis

**Context:** the unchanged local `GPT default` fixture repeated `ECONNRESET`.
The user limited further investigation and explicitly permitted stopping.

**Before/after:** the fixture rejected a WebSocket upgrade with HTTP 400 but
had no error listener on that server socket. Instrumentation located the reset
there; handling it let Pi fall back to HTTP streaming and complete the main and
observer requests, with all existing assertions intact. A final temporary copy
handled only that expected reset; other errors still throw. The complete local
suite then passed **17/17**, using the unchanged runtime extension.

**Expected behavior:** given a deliberately rejected upgrade, then handle the
expected disconnect and allow fallback assertions to complete. The failure
was fixture error handling, not evidence that the live observer path was broken.
[Node error-event documentation](https://nodejs.org/docs/latest-v25.x/api/events.html#error-events)
explains why an unhandled error event throws.

The reproducible fixture-only adaptation is
[`patches/ysk-routing-fixture.patch`](patches/ysk-routing-fixture.patch). It is not
applied to the installed checkout or loaded by the launcher. The original suite
failure remains in the earlier evidence; this is a corrected-fixture result,
not an unmodified-upstream pass. The three attempts, TAP output, and continuation
context are in [`evidence/ysk-transport-diagnosis/notes.md`](evidence/ysk-transport-diagnosis/notes.md).
No paid model requests, runtime transport changes, or upstream publication were
made. Diagnosis stopped after three attempts. The next task is the sub-agent
extension; selection is still pending the user's context.

Reproduce only the approved control run in a fresh output folder:

```bash
python3 -B pi/benchmark-ysk.py \
  --agent-dir /path/to/private/pi-test-agent \
  --output-dir /path/to/private/new-control-run \
  --corpus controls --workers 6
```

## Cross-project memory research

Research checked the latest upstream release, `v2.6.2`, and the installed
version, `2.6.0`. No shared binary was upgraded.

The new **cross-project profile** is a bounded set of standing preferences,
not a merger of every project's memories. Project pages and sessions remain
scoped. The profile can deliver package-manager, testing, workflow, and similar
defaults at session start. It never overrides current instructions or the
repository's rules, and never authorizes actions.

Arbitrary facts about a tool built in another project still require retrieval.
An agent can perform that retrieval in response to an ordinary question; the
user need not specify MCP calls. `memory_query` supports explicit project
scopes and global searches. Tool availability does not guarantee that a model
will choose the correct search on every prompt.

The upstream Pi extension forwards the session ID on MCP requests and injects
the server's `/handoff` response before the first agent turn. Profile delivery
uses that existing response path; it is not a reason to write a custom Pi
extension. Live delivery and natural-language cross-project retrieval passed.
These results demonstrate the selected cases, not guaranteed model behavior
for every future question.

Version warning: 2.6.1 fixes profile admission of project-specific instructions,
changes profile digest ordering, and fixes the Pi MCP initialized notification.
2.6.2 corrects profile rebuild guidance and fixes Pi schema references.
The separate 2.6.2 binary was approved and tested. A shared upgrade is not
approved and has not been performed.

Official sources:

- [Profile user guide, v2.6.2](https://github.com/akitaonrails/ai-memory/blob/v2.6.2/docs/cross-project-profile.md)
- [Profile design and limits, v2.6.2](https://github.com/akitaonrails/ai-memory/blob/v2.6.2/docs/design-cross-project-profile.md)
- [Retrieval and instruction precedence, v2.6.2](https://github.com/akitaonrails/ai-memory/blob/v2.6.2/docs/usage.md)
- [Release changes](https://github.com/akitaonrails/ai-memory/blob/v2.6.2/CHANGELOG.md)
- [Pi extension generator, v2.6.2](https://github.com/akitaonrails/ai-memory/blob/v2.6.2/crates/ai-memory-cli/src/commands/install_hooks.rs)
- [Pi skills](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/skills.md)
- [Pi MCP support](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md)

## Reproduce the memory checks

The release archive was verified against its published SHA-256:

```text
dc73118f772763a119b03d387f6f44f0b866d85498851b74aa5152944ef2e650
```

Source: [upstream v2.6.2 release](https://github.com/akitaonrails/ai-memory/releases/tag/v2.6.2).
Use the Linux x86_64 archive only on that architecture. Keep the extracted
binary outside shared installation paths.

Use an approved temporary server serving `~/.local/share/ai-memory` on a free
loopback port. Do not start a second writer for the same store; keep ai-memory's
normal single-instance lock, and never use `serve --force`. Our verification
server uses an explicit private configuration with embeddings disabled,
observation retention disabled, approval required for auto-improvement, and
the auto-improvement scheduler disabled. It runs with `--no-watcher`, no LLM
credentials, and no web/API service options.

Run from this repository, with paths and port from that approved server:

```bash
python3 pi/verify-ai-memory.py \
  --binary /path/to/private/ai-memory-2.6.2 \
  --endpoint http://127.0.0.1:PORT \
  --agent-dir /path/to/private/pi-test-agent \
  --model opencode-go/deepseek-v4.1-flash \
  --output /path/to/private/verification.json
```

Supply the selected provider's API key to the test process through a secure
environment, or use `PI_CODING_AGENT_DIR=/path/to/private/pi-test-agent` with
Pi's `/login` to authenticate the separate directory. Do not pass credentials
in the command line or reuse a shared authentication file. The runner generates
an unmodified extension with no `--apply`,
loads it explicitly, and disables unselected discovery. It does not install
skills or instructions. Expect nine `PASS` lines and exit code 0. A failure
returns a nonzero exit code and remains in the evidence artifact.

## Expected behavior

- Given an approved component, then verify it through real Pi sessions.
- Given two concurrent sessions in different projects, then each unscoped memory
  call resolves to its own project.
- Given a completed session, then its captured records remain available later.
- Given a question about another project's tool, then test retrieval of the
  stored fact; do not claim all prior content was automatically loaded.
- Given an enabled profile with applicable entries, then test that a new Pi
  session receives its bounded defaults without replacing repository rules.
- Given an excluded component, then do not configure it or delete its shared
  installation.
- Given a failed check, then report the failure and keep the port incomplete.

## Out of scope

- Guaranteed automatic recall of arbitrary facts from every project/session
  without retrieval. The upstream profile does not provide this contract.
  A broader automatic-recall design would need separate work and approval;
  it must preserve project isolation and avoid loading all history into context.
- Custom Pi memory extensions or changes to generated upstream code.
- Automatic profile application to shared or project `AGENTS.md` files.
- Additional roles beyond the six selected manager roles. The current integration
  is documented in `SUBAGENTS.md`; OpenCode delegation/models are not imported.
- The final decision to retain both harnesses or replace OpenCode.
