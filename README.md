# Agents

Claude Code agent stack with the [pstack](https://github.com/cursor/plugins/tree/main/pstack)
workflow. Opus on the Claude Pro plan is the main session. pstack roles that
name `go/<alias>` run on OpenCode Go models as separate worker processes.

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
           │  ~/.claude/rules/pstack-models.md   role ──▶ model
           │  ~/.claude/rules/pstack-go.md       go/<alias> ──▶ go-worker
           │
           ├── Agent tool ──▶ Claude subagents (opus/sonnet/haiku, Pro plan)
           │
           └── Bash, in background ──▶ go-worker run --model go/kimi-k3.1 ...
                                         │
                                         ▼
                        claude -p   CLAUDE_CONFIG_DIR=~/.claude-go
                        ANTHROPIC_BASE_URL = OpenCode Go
                        apiKeyHelper = bin/go-key (OPENCODE_API_KEY)
                        own Git worktree, report.md back to Opus
```

A **coordinator** is the main session that runs the pstack playbook. A
**worker** is one headless `claude -p` process that does one seat of a panel
and returns a report file.

## Quick Start

Prerequisites: Bash, curl, Git, and Python 3.11+. Linux also needs a
systemd user manager; Arch systems need `yay` when `ai-memory` is absent. macOS
needs Homebrew.

```sh
./apply.sh
source ~/.bash_aliases
claude            # once: log in with the Claude Pro plan, then /exit
./test.sh
go-worker doctor --live
```

Put the OpenCode Go key in `~/.config/ai-memory/env` as `OPENCODE_API_KEY=...`
before you use `go/` roles. ai-memory uses the same key for its LLM jobs.

The full validation checklist and daily usage are in
[`claude/README.md`](claude/README.md).

## Components

| Component | Documentation |
| --- | --- |
| Claude Code, pstack, OpenCode Go workers | [claude/README.md](claude/README.md) |
| ai-memory service | [ai-memory/README.md](ai-memory/README.md) |
| Bash entry point | [shell/README.md](shell/README.md) |
| Shared helpers | [lib/README.md](lib/README.md) |
| Global agent policy | [CLAUDE.md](CLAUDE.md) |

## What apply.sh changes

| Path | Owner | Content |
| --- | --- | --- |
| `~/.local/bin/claude` | Claude Code installer | Native Claude Code. |
| `~/.claude/CLAUDE.md` | apply.sh | Copy of the repository `CLAUDE.md`, plus the `@RTK.md` import that RTK adds. |
| `~/.claude/rules/{pstack-models,pstack-go}.md` | apply.sh | Managed copies of `claude/rules/`. |
| `~/.claude/rules/ai-memory.md` | ai-memory | Generated routing instructions. |
| `~/.claude/settings.json` | shared | apply.sh sets `model` and adds `go-worker` allow rules; ai-memory and RTK add hooks; the plugin manager adds `enabledPlugins`. |
| `~/.claude/skills/` | ai-memory | Five ai-memory skills. |
| `~/.claude-go/` | apply.sh | Worker profile: `CLAUDE.md`, `settings.json` (OpenCode Go base URL, `apiKeyHelper`), RTK hook. |
| `~/.local/bin/go-worker` | apply.sh | Symlink to `bin/go-worker`. |
| `~/.bash_aliases`, `~/.bash_profile` | apply.sh | Marked blocks only. The retired OpenCode block is removed. |

apply.sh does not delete the old OpenCode installation (`~/.opencode`,
`~/.config/opencode`, the OpenCode server service). Remove those by hand when
you no longer need them.

`./test.sh --repo-only` runs the deterministic fixtures with a temporary HOME
and fake executables. It never changes the workstation and never uses the
network.
