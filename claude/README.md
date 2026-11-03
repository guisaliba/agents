# Claude Code, pstack, and workers

## Context

- `rules/` holds the two rule files that apply.sh copies to
  `~/.claude/rules/`. Claude Code loads every file in that directory into each
  main session.
  - `pstack-models.md` is the pstack role table. pstack reads it in place of the
    `/pstack:setup-pstack` output. Its `#` lines are comments in the format that
    the pstack Claude Code adapter specifies for this file, and the `# budget`
    line is the one pstack parses.
  - `pstack-workers.md` tells the coordinator how to run a `worker/<alias>`
    role through `claude-worker`.
- `worker/CLAUDE.md` is the contract for every worker
  (`~/.claude-worker/CLAUDE.md`).
- `worker/provider.env` holds every provider-specific setting.
- `worker/models.tsv` is the roster: alias, provider model id, model family,
  and the monthly allowance in USD.

Do not run `/pstack:setup-pstack`. It accepts only Claude models that it can
detect, so it would drop every `worker/` entry. Edit `rules/pstack-models.md` in
this repository and run `./apply.sh` again.

## Which instructions load where

| Session | User-level instructions | Rules | Project `CLAUDE.md` |
| --- | --- | --- | --- |
| Main (`claude`) | `~/.claude/CLAUDE.md` (the repository `CLAUDE.md`) | `~/.claude/rules/*.md` | Loaded |
| Worker (`claude-worker`) | `~/.claude-worker/CLAUDE.md` (the worker contract) | none | Loaded from the worker's checkout |

A worker does not load `~/.claude/CLAUDE.md`, because `CLAUDE_CONFIG_DIR` moves
its user-level directory to `~/.claude-worker`. The worker contract repeats the
rules a worker needs: the language rule, the evidence rule, and the report
format.

## Role table

| Role | Model | Plan |
| --- | --- | --- |
| Main session, judgment, prose, hardest tasks | Opus | Claude Pro |
| Feature, refactoring, bug fix | `worker/kimi-k2.7-code` | worker provider |
| Perf issue | `worker/glm-5.3` | worker provider |
| Hillclimb, `how` explorer, `why` investigators, swarm workers | `worker/deepseek-v4.1-flash` | worker provider |
| Arena and architect runners | Opus (`inherit-parent`), `worker/kimi-k3.1`, `worker/glm-5.3` | both |
| Arena cross-judge | `worker/kimi-k3.1`, `worker/glm-5.3` | worker provider |
| Interrogate reviewers | `worker/kimi-k3.1`, `worker/glm-5.3`, `worker/gpt-6-luna`, `worker/deepseek-v4.1-flash` | worker provider |

With OpenCode Go, the bulk work goes to the large allowances (DeepSeek V4.1
Flash $100, Kimi K2.7 Code $60). The frontier models (Kimi K3.1, GLM-5.3, GPT 6
Luna, $15 each on Go) only take panel seats.

## claude-worker

```text
claude-worker run --model worker/<alias> --dir <path> --brief <file> --report <file> [--readonly]
claude-worker models          # provider and roster
claude-worker doctor [--live] # profile, key, live model ids, optional one live run
claude-worker usage           # tokens per model from the local ledger
claude-worker-key             # the apiKeyHelper; prints the key, or why it is missing
```

- A write seat runs with `--permission-mode acceptEdits` and the tools
  `Read,Edit,Write,Glob,Grep,Bash` in the directory that `--dir` names; the
  coordinator creates that worktree first. A `--readonly` seat runs with
  `dontAsk` and `Read,Glob,Grep,Bash`: no edit tools, but Bash, so it can run
  tests. This matches the pstack Claude Code adapter, which maps `readonly` to
  the `Explore` subagent. The coordinator checks `git status` after the seat.
- Every seat runs with `--permission-prompts none` and without the `Agent` and
  `WebSearch` tools, so a worker cannot fan out further.
- The worker gets an explicit, small environment. The coordinator's
  `CLAUDECODE` and `ANTHROPIC_*` variables do not reach it.
- Outputs per seat: `report.md`, `report.md.meta.json`, `report.md.raw.json`,
  `report.md.stderr.log`. The ledger is
  `~/.local/state/claude-worker/runs.tsv`.

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
2. **Worker profile and key.** Run `claude-worker doctor`. Expected: every
   check `ok`. The roster model ids are a **hypothesis** derived from the
   OpenCode Go documentation; a failed id check prints the live ids, so correct
   `worker/models.tsv` from that output.
3. **A non-Claude model inside Claude Code.** Run `claude-worker doctor --live`.
   Expected: the smoke worker replies `READY`. Then give one real write seat:
   `claude-worker run --model worker/kimi-k2.7-code --dir <scratch-worktree> ...`
   with a small edit task. Expected: the edit exists and the report lists it.
4. **Routing by instruction.** In a scratch repository, run
   `/pstack:arena add a --json flag to <a small script>. 3 candidates.`
   Expected: Opus starts `claude-worker` background commands for the `worker/`
   seats, briefs appear under `.git/claude-worker/`, and `claude-worker usage`
   shows new runs. Failure mode: Opus spawns Claude subagents for those seats
   instead.
5. **Cross-family judge.** In the same arena run, expected: the judge runs as a
   `worker/` seat (`--readonly`), not skipped.
6. **Interrogate.** Run `/pstack:interrogate` on that branch. Expected: verified
   findings with commands, from more than one model family.
7. **ai-memory.** Start `claude` in a repository, work for a few turns, and
   quit. Plain `claude` resumes that same managed session, and a managed session
   ends without a handoff. Run `claude --fresh` to start a new session in the
   same workstream. Expected: `AI_MEMORY_RUN_ID`, `AI_MEMORY_WORKSTREAM_ID`, and
   `AI_MEMORY_PREVIOUS_SESSION_HISTORY` are set, and the new session can
   summarize the previous one from that history file.
   `~/.claude-worker/settings.json` has no ai-memory hooks.
8. **RTK.** In both profiles, a `git status` tool call is rewritten to
   `rtk git status` (see `rtk gain`). Neither `settings.json` has an RTK proxy
   `ANTHROPIC_BASE_URL`.
9. **Capacity.** After one week of normal use, compare `claude-worker usage`
   with the provider console. For OpenCode Go, decide Go or Go Plus from the
   5-hour and weekly limits of the frontier models.
10. **Pro quota.** Watch the Claude Pro usage meter on panel-heavy days. If it
    runs out first, move `judgment and prose` or `hardest tasks` to a
    `worker/` model.
