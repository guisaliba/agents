# Pi subagent manager: setup, operation, and evidence

## Context

The user selected `championswimmer/pi-subagent-manager`, approved automatic
starts, selected six role assignments, and approved local integration patches.
The selected version is `0.20.0`, commit
`1f037b176070b8867e00e348a08615d04d684ee8`.

The manager, Learn, and YSK do not have matching child interfaces without
adaptation. The launcher stages reviewed patches; installed upstream files
remain unchanged. The patches are local maintenance work, not upstream fixes.

### Selected roles

| Role | Work | Provider/model | Thinking |
| --- | --- | --- | --- |
| architect | Plans, decisions, authorized coordination | `openai/gpt-6.1-sol` | `medium` |
| coder | Implementation and Learn visuals | `openai/gpt-6-luna` | `max` |
| researcher | Source-backed investigation | `opencode-go/deepseek-v4.1-flash` | `high` |
| reviewer | Non-mutating defect review | `openai/gpt-6.1-sol` | `low` |
| tasker | Short bounded work | `opencode-go/claude-haiku-5-5` | `high` |
| writer | Prose from supplied/local evidence | `opencode-go/mimo-v2.6-pro` | `medium` |

Haiku's exact registry ID uses `5-5`, not `5.5`. All six assignments made
successful live requests at the selected effective thinking levels. This is
execution evidence, not a broad model-quality comparison.

The source of truth is [subagent-config.json](subagent-config.json). Settings-only
`.yml` overrides keep bundled instructions; they do not create new roles.
There are no separate Mermaid/SVG agent types. Their original Learn documents
are task instructions read by coder.

### Observer versus child

An **observer** is a separate tool-free model request that checks conversation
context. YSK's main observer needs no subagent manager and spawns no Pi session.
A **child session** is an independent managed Pi SDK session inside the same
process. This manager does not start a separate Pi process for each child.

```text
Main Pi conversation                         selected main model
  +-- YSK observer request                   Luna/max
  |
  +-- child SDK session                      assigned role model/effort
       +-- permitted local tools
       +-- isolated visual tools             coder only
       +-- YSK observer request              Luna/max
            +-- note -> main session inbox
```

Child observer model and thinking are explicit, including for non-GPT workers.
No process-wide child identity environment changes are made. Each child has
separate observer state; feedback knowledge stays under upstream's normal
profile store. Main `/ysk off` prevents new child checks. Child checks retain
upstream's six-turn schedule. Short jobs may produce no observer request.

## Before/after

Before, the launcher did not expose delegation. Learn expected `subagent` and
`__pi_interactive_subagents.registerToolExtension`. YSK's relay expected
separate-process environment variables, and its checks required a UI.

After, `--subagents` selects the reviewed manager and activates `agent_*` tools.
The scoped-model list includes the six approved assignments. Learn's staged
visualize skill uses `agent_spawn(type="coder")`. Factories load permitted
rendering tools inside the child, with session-ID-keyed source paths,
factory-local state, sequential tool execution, and source restoration on
reopening. Chromium keeps its sandbox enabled and uses the installed Linux
executable. YSK uses explicit child options and the existing parent inbox.

The integration files are:

- [launch.py](launch.py): explicit manager/model/tool selection and resume picker.
- [resources.py](resources.py): upstream hash checks and temporary patch staging.
- [subagent-source.json](subagent-source.json): manager pin and reviewed hashes.
- [child-extensions.ts](child-extensions.ts): child tool/observer factories and
  approved instruction loading.
- [patches/subagent-child-runtime.patch](patches/subagent-child-runtime.patch).
- [patches/learn-child-visuals.patch](patches/learn-child-visuals.patch).
- [patches/ysk-sdk-child.patch](patches/ysk-sdk-child.patch).
- [renderer/](renderer/): locked private runtime dependencies, Mermaid CLI
  `11.16.0`. The original Learn lockfile has a broken author-local macOS link;
  its failed install is retained outside the repository.

### Private setup

Use the repository's `install.sh`, then `pi-port login`, `pi-port doctor`, and
`pi-port`. The installer provisions the exact reviewed sources, locked runtime
and renderer dependencies, six settings-only overrides, and a permanent memory
service. See [the current installation guide](../README.md).

No shared settings or authentication are copied. YSK is explicitly selected by
the normal wrapper; `/ysk off` disables new checks. The lower-level launcher can
still omit `--ysk-model` or `--subagents` for isolated verification.

### Settings and controls

Settings live at `<agent-dir>/subagent-manager/settings.json`; definitions and
settings-only role overrides live at `<agent-dir>/subagent-manager/agents/`.
Trusted project settings override user settings. This launcher declines project
trust, so project manager overrides are not loaded.

Selected policies:

- **Opportunistic:** the main model decides when work merits delegation.
  Orchestration mode instead asks it to delegate all execution. Neither is an
  OS permission boundary.
- **Pick First (scoped):** ordered exact `models` preferences must be available
  and in the main scope. No eligible preference means a spawn error. This is
  selection at session setup, not a model-error retry chain.
- **Allowed (except blocked):** only exact allowed tools are exposed. Architect
  alone has descendant delegation among the bundled roles.
- Three levels including main, sixteen concurrent threads, sixty-four retained
  threads. Waiting parents count. Full capacity fails rather than queues.
- Final Recap off. Detached completion already wakes an idle main agent; Recap
  would combine completions and can add model turns.
- `pi-status` cost display; no extra footer package is installed.

A settings-only override changes model, thinking, or tools without forking the
role prompt. A full `.md` fork replaces the bundled role and stops receiving
its prompt updates. This port uses settings-only overrides. Suggestions in
`modelSuggestions` only rank picker results; they never assign models.

### Commands, tools, and navigation

- `/agents`: settings; Ctrl+S saves.
- `/agents types`: role browser, model ordering, tools, and overrides.
- `/agents tree`: tree, live transcript, steering, stop, output, and transcript
  actions. Enter watches; Tab changes focus; Escape returns.
- `/agents reload`: reload definitions and settings.
- `/agents reap`: confirmation before forgetting eligible retained threads.
  It frees slots but leaves transcript files. Forgotten threads cannot resume.
- `/agents import`: optional conversion using the main model. This port imports
  no external or OpenCode roles. Cancel any import offer.

Model-facing tools are `agent_types`, `agent_spawn`, `agent_wait`, `agent_steer`,
`agent_status`, `agent_update`, `agent_pause`, `agent_stop`, and `agent_output`.
Independent siblings start with `wait:false` before waiting. Waiting on the
first foreground child before starting another is sequential.

A child returns only its final answer; progress updates are separate. It starts
from a frozen snapshot of its lexical parent, without the parent's system
prompt. This port explicitly supplies the approved Pi instructions to children.
Independent roots have no inherited history and suit clean-context review.

While children run, Left at the start of the main draft opens the browser.
Right at the end collapses the widget for that session. Full/minimal widget
modes, icons, and loader styles are available; no font changes were made.
Pi has one custom-editor slot, and unrelated overlays can conflict. The native
Learn question/quiz path worked with the manager in the retained terminal test.

### Stop and resume

- Escape aborts the main turn, not its children.
- Spawn timeout reports status; it does not kill the child.
- `agent_stop` or the tree Stop action cancels a subtree cooperatively.
- Pause, completion, stop, and failure retain sessions for steering/resume.
- Reopening interrupted work restores it paused, not automatically running.
- Use launcher `--resume` and select the **main** session to restore the managed
  tree. `--continue` may select a recently active child. Opening a child directly
  gives an unmanaged conversation; do not do so while its parent runs it.
- Reaping leaves files but removes management/resume eligibility.

No option here is a sandbox, a guaranteed external-process kill, or a spending
cap. Bash retains the current account's OS permissions. Concurrent workers need
explicitly separate owned files. Main-session extension/MCP tools can be bridged
when allowed, but they retain main resources/context. Main RTK and ai-memory
lifecycle hooks are not automatically copied into every child; separate child
transcripts are not proof of child lifecycle capture in ai-memory.

## Expected behavior and verification

Given a new child, then use its selected model and thinking. The live team test
verified all six roles, automatic starts, owned artifacts, an inspected SVG,
and eight passing fixture tests. See
[evidence/subagent-live-attempt-1/result.json](evidence/subagent-live-attempt-1/result.json).
The fixture is a small functional test, not evidence of general role quality.

Given parallel visuals, then use separate sources and images. Given a reopened
visual session, then retain its staged source. Original failures and corrected
renders remain in `evidence/visual-isolation-*.json` and
`evidence/visual-resume-*.json`. The final render check is in
`evidence/visual-final-green.json`; four verifiable PNGs are retained in
`evidence/visual-isolation-artifacts/`.

Given a useful child observer finding, then deliver it to the parent once.
[evidence/child-relay-live-attempt-1/result.json](evidence/child-relay-live-attempt-1/result.json)
records a real Luna/max note about inconsistent synthetic billing receipts.
It proves generation/relay, not a real billing defect or broad detection quality.
The final repeat in `evidence/child-relay-live-attempt-2/` failed its expected-note
assertion. Its `diagnosis.json` shows a real Luna/max check returned `none`;
no note existed to deliver. This is a retained detection-reliability gap, not
proof of a transport failure. Reliable detection of this fixture is not claimed.

Given the original teach workflow, then probe the synthetic learner, gather the
goal through native UI, delegate research, present/approve the plan, teach and
quiz, delegate a Mermaid render, inspect it, and log its PNG embed.
[evidence/learn-workflow-live-attempt-3/result.json](evidence/learn-workflow-live-attempt-3/result.json)
and its `fixture/lesson.md` and `viz/` image retain that complete path. This test
supplies synthetic student answers; it does not measure the real user's knowledge
or prove learning effectiveness. Obsidian itself was not launched or inspected.

The first Learn runner missed native plan approval. The second runner stalled
on an overly strict terminal-frame match. Both failures remain in their original
attempt folders; neither is relabeled as passing.

Regression evidence:

- `evidence/subagent-final-suite.tap`: 449/449 manager tests, scripted/offline.
- `evidence/subagent-final-typecheck.log`: patched integration typecheck passed.
  The manager test/typecheck dependencies are Pi `0.99.2`; live tests and actual
  resource/render discovery used installed Pi `1.1.0`. These are distinct checks.
- `evidence/ysk-sdk-final-regression.tap`: 17/17 YSK tests with the previously
  approved fixture-only upgrade-socket correction; not an unmodified suite.
- `python3 -B pi/test-launch.py -v`: focused launcher checks.
- `evidence/subagent-final-discovery.json`: real zero-request resource discovery.

The first patched-suite runner omitted release files and ESM package metadata;
its failing artifact remains. The corrected suite passed without changing its
assertions. A typecheck caught two unused constants; they were removed, and both
red and green logs remain.

Reproduce live checks into **new** output directories:

```bash
python3 -B pi/verify-subagents.py --agent-dir PROFILE \
  --memory-binary BINARY --memory-endpoint ENDPOINT --output-dir NEW_TEAM_DIR
python3 -B pi/verify-child-relay.py --agent-dir PROFILE \
  --memory-binary BINARY --memory-endpoint ENDPOINT --output-dir NEW_RELAY_DIR
python3 -B pi/verify-learn-workflow.py --agent-dir PROFILE \
  --memory-binary BINARY --memory-endpoint ENDPOINT --output-dir NEW_LEARN_DIR
```

These commands make paid or subscription-consuming requests. Native Learn
verification needs a POSIX terminal. No approval is requested per subagent start.

### Cost evidence

[evidence/subagent-integration/cost-summary.json](evidence/subagent-integration/cost-summary.json)
separates main/child session usage from observer side requests and includes
failed test attempts. The six retained live runs total **$1.075546** in reported
catalog estimates, including $0.115718 for the final no-note relay repeat. It excludes inherited conversation usage from child totals.
These are catalog USD estimates, not invoices or subscription deductions. Older
root observer records without session IDs are excluded rather than guessed.
Requests with absent usage cannot be priced. No strict spending cap is claimed.

### Remaining scope

The selected integration and tested Learn path have live evidence. The permanent
Linux setup is now provisioned and verified; see `../README.md`. Additional MCP
selection and TUI changes remain separate tasks. Broad web-search coverage, all
manager UI actions with live models, and real Obsidian display are not established
by the synthetic tests. Installed OpenCode and shared configuration remain
unchanged; the old repository setup is removed on this branch. Plannotator remains
excluded.

## Sources

Current upstream operating contracts, pinned to the reviewed manager commit:

- [README](https://github.com/championswimmer/pi-subagent-manager/blob/1f037b176070b8867e00e348a08615d04d684ee8/README.md).
- [Settings](https://github.com/championswimmer/pi-subagent-manager/blob/1f037b176070b8867e00e348a08615d04d684ee8/docs/settings.md).
- [Threads](https://github.com/championswimmer/pi-subagent-manager/blob/1f037b176070b8867e00e348a08615d04d684ee8/docs/threads.md).
- [Tools/UI](https://github.com/championswimmer/pi-subagent-manager/blob/1f037b176070b8867e00e348a08615d04d684ee8/docs/tools-and-ui.md).
- [Role overrides](https://github.com/championswimmer/pi-subagent-manager/blob/1f037b176070b8867e00e348a08615d04d684ee8/docs/custom-agents.md).
- [Bundled definitions](https://github.com/championswimmer/pi-subagent-manager/tree/1f037b176070b8867e00e348a08615d04d684ee8/agents).

Pi's official [SDK](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/sdk.md),
[extensions](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/extensions.md),
[packages](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/packages.md),
and [security](https://github.com/earendil-works/pi/blob/v1.1.0/packages/coding-agent/docs/security.md)
define the host mechanisms and limits. Learn and YSK pins remain in
[sources.json](sources.json). Historical upstream model audits are advisory;
they do not override the user's selected assignments or constitute local model
quality evidence.
