# pstack roles on OpenCode Go workers

This rule extends the pstack Claude Code adapter
(`<pstack>/docs/harness/claude-code.md`). It replaces the adapter row that says
"a non-Claude slug: omit `model`" for every value that starts with `go/`. All
other adapter rows stay in force.

## Why this rule exists

The main session runs Opus on the Claude Pro plan. Claude Code subagents can
only run Claude models on that same plan. A `go/<alias>` role value therefore
runs as a separate headless Claude Code process, `go-worker`, which uses the
OpenCode Go key and a separate configuration directory (`~/.claude-go`). The
worker never touches the Pro login.

## Which values route to a worker

- A role value `go/<alias>` routes to `go-worker`. `go-worker models` prints the
  aliases, the OpenCode Go model ids, and the model family of each.
- A Claude value (`opus xhigh`, `sonnet high`, `inherit-parent`, `auto`) uses
  the Agent tool as the adapter says. Nothing changes for those.
- Model family for pstack family rules (the arena cross-judge must come from a
  family other than the parent's): the main session is family `claude`. A
  `go/<alias>` value has the family that `go-worker models` prints.
- The `/setup-pstack` budget and the reasoning-level adjustments do not apply to
  `go/` values. Use the value as written. Never append an effort token to it.

## How to run a worker seat

Do this in place of one Agent tool call.

1. **Location.** A writing seat (implementation, arena runner, architect runner,
   interrogate adversary, swarm worker that edits) gets its own Git worktree:
   `git worktree add <repository>-worktrees/go-<role>-<n> <base-ref>`. Copy
   uncommitted changes into it when the skill says so. A read-only seat (arena
   cross-judge, how explorer, why investigator) runs in the checkout it reads.
2. **Brief.** Write the brief to a file under
   `$(git rev-parse --path-format=absolute --git-common-dir)/go-worker/<utc-timestamp>-<role>-<n>/brief.md`.
   That directory is inside `.git`, so a brief is never committed. The brief
   holds everything the Agent tool prompt would hold: the user's goal in your own
   words, the scope, the success criteria, the exact instructions the calling
   skill gives that role, and absolute paths for every file the worker must
   read. A worker has no access to this conversation. Where pstack says to pass
   a file (for example the arena `references/runner-prompt.md`, or the
   `poteto-mode` SKILL.md that a `poteto-agent` reads first), give its absolute
   path. Never put a secret in a brief.
3. **Launch.** Run one Bash command per seat with `run_in_background: true`, all
   seats of one panel in the same message:

   ```bash
   go-worker run --model go/<alias> --dir <worktree-or-checkout> \
     --brief <brief.md> --report <same-directory>/report.md [--readonly]
   ```

   Add `--readonly` for a read-only seat.
4. **Collect.** Wait for every background command to finish. `go-worker` exits 0
   on success, 1 when the worker run failed, 2 on a usage error, and 3 when the
   worker profile or the OpenCode Go key is not configured. Read `report.md` and
   `report.md.meta.json` for each seat.
5. **Own the result.** Treat each report like a subagent result. Review the
   worktree diff yourself and write your own summary. Do not pass a report
   through.

## Failures

- Exit 1: count the seat as a dropout and apply the calling skill's dropout rule
  (for example arena continues with N-1). Say which seat dropped and why.
- Exit 3: stop routing to OpenCode Go for this task. Tell the user the reason
  that `go-worker` printed, run the seat with `inherit-parent` instead, and say
  so in the reply.
- A follow-up, retry, or next round always starts a fresh worker with a
  consolidated brief (the original brief, every later directive, and the prior
  report). Workers keep no state between runs.

## Cost visibility

`go-worker usage` summarizes the token usage that each worker reported, per
model, from the local ledger. Use it when the user asks how much OpenCode Go
capacity a task used.
