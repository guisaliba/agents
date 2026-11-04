# Agents

Claude Code agent stack with the [pstack](https://github.com/cursor/plugins/tree/main/pstack)
workflow. Opus on the Claude Pro plan is the main session. pstack roles that
name `worker/<alias>` run on models from a second provider as separate worker
processes. The current worker provider is OpenCode Go.

The dotfiles installer clones this repository into
`~/.local/share/dotfiles/agents`. This repository owns the agent setup; it does
not depend on the dotfiles checkout.

## Context

The previous `main` installed an OpenCode V2 stack. This setup replaces it. It
keeps two components from that stack, ai-memory and RTK, and drops the rest
(OpenCode, Plannotator, Learn, the MCP servers, and the skill catalog). pstack
supplies the workflow skills.

Claude Code subagents can only run Claude models on the plan of the main
session. pstack gets its counter-arguments from model diversity (rival designs
in `/pstack:arena`, adversaries in `/pstack:interrogate`, a judge from another
model family). This setup adds that diversity without leaving Claude Code and
without routing the Pro login through a third-party tool:

```text
 You ──▶ claude (Opus, Claude Pro login, ~/.claude)
           │  pstack plugin: /pstack:poteto-mode, arena, interrogate, ...
           │  ~/.claude/rules/pstack-models.md    role ──▶ model
           │  ~/.claude/rules/pstack-workers.md   worker/<alias> ──▶ claude-worker
           │
           ├── Agent tool ──▶ Claude subagents (opus/sonnet/haiku, Pro plan)
           │
           └── Bash, in background ──▶ claude-worker run --model worker/kimi-k3.1 ...
                                         │
                                         ▼
                        claude -p   CLAUDE_CONFIG_DIR=~/.claude-worker
                        ANTHROPIC_BASE_URL = provider (claude/worker/provider.env)
                        apiKeyHelper = claude-worker-key
                        --dir: a worktree that Opus creates (write seat)
                        or the checkout it reads (read-only seat);
                        report.md back to Opus
```

A **coordinator** is the main session that runs the pstack playbook. A
**worker** is one headless `claude -p` process that does one seat of a panel
and returns a report file. A **worker provider** is the Anthropic-compatible
model gateway that workers call.

## Change the worker provider

Two files hold everything provider-specific:

- `claude/worker/provider.env`: base URL, model list URL, background model,
  smoke-test alias, and the file and variable that hold the API key.
- `claude/worker/models.tsv`: the roster of aliases, provider model ids, model
  families, and allowances.

Edit both, update the `worker/<alias>` values in
`claude/rules/pstack-models.md` when aliases change, then run `./apply.sh` and
`claude-worker doctor`.

## Quick Start

Prerequisites: Bash, curl, Git, and Python 3.11+. Linux also needs a systemd
user manager and `bwrap` and `socat` (the Claude Code sandbox for read-only
worker seats; Arch: `sudo pacman -S bubblewrap socat`); Arch systems need
`yay` when `ai-memory` is absent. macOS needs Homebrew.

```sh
./apply.sh
source ~/.bash_aliases
claude            # once: log in with the Claude Pro plan, then /exit
./test.sh
claude-worker doctor --live
```

For the OpenCode Go provider, put the key in `~/.config/ai-memory/env` as
`OPENCODE_API_KEY=...` before you use `worker/` roles. You own that file;
`apply.sh` never rewrites it. ai-memory uses the same key for its LLM jobs when
the file also sets `AI_MEMORY_LLM_PROVIDER=opencode` and `AI_MEMORY_LLM_MODEL`
(see [ai-memory/README.md](ai-memory/README.md#llm)).

The full validation checklist and daily usage are in
[`claude/README.md`](claude/README.md).

## Components

| Component | Version | Documentation |
| --- | --- | --- |
| Claude Code, pstack, workers | Claude Code 2.1.287 or newer; pstack from the `cursor-plugins` marketplace | [claude/README.md](claude/README.md) |
| ai-memory service | 3.3.1 | [ai-memory/README.md](ai-memory/README.md) |
| RTK | v1.1.0 | `lib/rtk.bash` |
| Bash entry point | | [shell/README.md](shell/README.md) |
| Shared helpers | | [lib/README.md](lib/README.md) |
| Global agent policy | | [CLAUDE.md](CLAUDE.md) |

## What apply.sh changes

| Path | Owner | Content |
| --- | --- | --- |
| `~/.local/bin/claude` | Claude Code installer | Native Claude Code. |
| `~/.claude/CLAUDE.md` | apply.sh | The repository `CLAUDE.md` plus a last `@RTK.md` line. The source has no import, because Claude Code resolves `@RTK.md` relative to the file and the repository has no `RTK.md`. |
| `~/.claude/rules/{pstack-models,pstack-workers}.md` | apply.sh | Managed copies of `claude/rules/`. |
| `~/.claude/rules/ai-memory.md` | ai-memory | Generated routing instructions. |
| `~/.claude/settings.json` | shared | apply.sh sets `model`, adds `claude-worker` allow rules, and enables the built-in `cc-plugin-you-should-know@builtin` mod; ai-memory and RTK add hooks; the plugin manager adds the pstack entry to `enabledPlugins`. |
| `~/.claude/skills/` | ai-memory | Five ai-memory skills. |
| `~/.claude-worker/` | apply.sh | Worker profile: `CLAUDE.md` (from `claude/worker/contract.md`, plus the `@RTK.md` line), `settings.json` (provider base URL, `apiKeyHelper`), RTK hook. |
| `~/.local/bin/claude-worker`, `~/.local/bin/claude-worker-key` | apply.sh | Symlinks to `bin/`. |
| `~/.bash_aliases`, `~/.bash_profile` | apply.sh | Marked blocks only. The retired OpenCode block is removed. |

When a managed copy (`CLAUDE.md`, a pstack rule, or the worker `CLAUDE.md`)
differs from the repository file, apply.sh first copies it to
`<file>.bak-<UTC timestamp>` next to it, then replaces it. A backup does not end in
`.md`, so Claude Code does not load it as a rule.

apply.sh does not delete the old OpenCode installation (`~/.opencode`,
`~/.config/opencode`, the OpenCode server service), the old shared skills in
`~/.agents/skills`, or an old `~/.claude-go` profile from an earlier build of
this branch. Remove those by hand when you no longer need them.

`./test.sh --repo-only` runs the deterministic fixtures with a temporary HOME
and fake executables. It never changes the workstation and never uses the
network.
