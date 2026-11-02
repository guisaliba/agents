# Claude Code, pstack, and OpenCode Go workers

## Context

- `rules/` holds the three rule files that apply.sh copies to
  `~/.claude/rules/`. Claude Code loads every file in that directory into each
  session.
  - `harness-map.md` maps the OpenCode names in `AGENTS.md` to Claude Code
    names, so `AGENTS.md` stays unchanged.
  - `pstack-models.md` is the pstack role table. pstack reads it in place of the
    `/pstack:setup-pstack` output.
  - `pstack-go.md` tells the coordinator how to run a `go/<alias>` role through
    `go-worker`.
- `worker/CLAUDE.md` is the contract for every worker (`~/.claude-go/CLAUDE.md`).
- `go-models.tsv` is the roster: alias, OpenCode Go model id, model family, and
  the Go monthly allowance in USD.

Do not run `/pstack:setup-pstack`. It accepts only Claude models that it can
detect, so it would drop every `go/` entry. Edit `rules/pstack-models.md` in this
repository and run `./apply.sh` again.

## Role table

| Role | Model | Plan |
| --- | --- | --- |
| Main session, judgment, prose, hardest tasks | Opus | Claude Pro |
| Feature, refactoring, bug fix | `go/kimi-k2.7-code` | OpenCode Go |
| Perf issue | `go/glm-5.3` | OpenCode Go |
| Hillclimb, `how` explorer, `why` investigators, swarm workers | `go/deepseek-v4.1-flash` | OpenCode Go |
| Arena and architect runners | Opus (`inherit-parent`), `go/kimi-k3.1`, `go/glm-5.3` | both |
| Arena cross-judge | `go/kimi-k3.1`, `go/glm-5.3` | OpenCode Go |
| Interrogate reviewers | `go/kimi-k3.1`, `go/glm-5.3`, `go/gpt-6-luna`, `go/deepseek-v4.1-flash` | OpenCode Go |

The bulk work goes to the large Go allowances (DeepSeek V4.1 Flash $100,
Kimi K2.7 Code $60). The frontier Go models (Kimi K3.1, GLM-5.3, GPT 6 Luna,
$15 each on Go) only take panel seats.

## go-worker

```text
go-worker run --model go/<alias> --dir <path> --brief <file> --report <file> [--readonly]
go-worker models          # roster
go-worker doctor [--live] # profile, key, live model ids, optional one live run
go-worker usage           # tokens per model from the local ledger
```

- A write seat runs with `--permission-mode acceptEdits` and the tools
  `Read,Edit,Write,Glob,Grep,Bash` in its own worktree. A `--readonly` seat runs
  with `dontAsk` and read-only tools.
- Every seat runs with `--permission-prompts none` and without the `Agent` and
  `WebSearch` tools, so a worker cannot fan out further.
- The worker gets an explicit, small environment. The coordinator's
  `CLAUDECODE` and `ANTHROPIC_*` variables do not reach it.
- Outputs per seat: `report.md`, `report.md.meta.json`, `report.md.raw.json`,
  `report.md.stderr.log`. The ledger is
  `~/.local/state/go-worker/runs.tsv`.

## Daily use

```text
/pstack:poteto-mode <goal>. Done means <check>. Keep <behavior>.
/pstack:arena second opinion on this design. the storage choice is expensive to change.
/pstack:interrogate the whole branch, skeptically. no nitpicks.
```

Opus restates the goal, picks the playbook, and runs each seat on the model the
role table names.

## Validation checklist

Each item tests one open question. Record the result in the PR that promotes
this branch to `main`.

1. **Pro login, Opus main.** Run `claude`, then `/status`. Expected: a claude.ai
   login, model `opus`, no `Anthropic base URL` line.
2. **Worker profile and key.** Run `go-worker doctor`. Expected: every check
   `ok`. The roster model ids are a **hypothesis** derived from the OpenCode Go
   documentation; a failed id check prints the live ids, so correct
   `go-models.tsv` from that output.
3. **A non-Claude model inside Claude Code.** Run `go-worker doctor --live`.
   Expected: the DeepSeek worker replies `READY`. Then give one real write seat:
   `go-worker run --model go/kimi-k2.7-code --dir <scratch-worktree> ...` with a
   small edit task. Expected: the edit exists and the report lists it.
4. **Routing by instruction.** In a scratch repository, run
   `/pstack:arena add a --json flag to <a small script>. 3 candidates.`
   Expected: Opus starts `go-worker` background commands for the `go/` seats,
   briefs appear under `.git/go-worker/`, and `go-worker usage` shows new runs.
   Failure mode: Opus spawns Claude subagents for those seats instead.
5. **Cross-family judge.** In the same arena run, expected: the judge runs as a
   `go/` worker (`--readonly`), not skipped.
6. **Interrogate.** Run `/pstack:interrogate` on that branch. Expected: verified
   findings with commands, from more than one model family.
7. **ai-memory.** Start `claude` in a repository, work for a few turns, quit,
   and start again. Expected: a handoff appears. `~/.claude-go/settings.json`
   has no ai-memory hooks.
8. **RTK.** In both profiles, a `git status` tool call is rewritten to
   `rtk git status` (see `rtk gain`).
9. **Capacity.** After one week of normal use, compare `go-worker usage` with
   the OpenCode Go console. Decide Go or Go Plus from the 5-hour and weekly
   limits of the frontier models.
10. **Pro quota.** Watch the Claude Pro usage meter on panel-heavy days. If it
    runs out first, move `judgment and prose` or `hardest tasks` to a `go/` model.

## Known open decision

`AGENTS.md` says: ask three motivation questions before a plan.
`/pstack:poteto-mode` says: restate the goal and proceed without waiting. Both
load into the same session. This setup does not resolve the conflict, because
`AGENTS.md` stays unchanged for now. Decide which rule wins when you refine
`AGENTS.md`.
