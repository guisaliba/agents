# Agents

OpenCode V2 agent stack with one primary M4 server and Linux/macOS clients.

The dotfiles installer clones this repository into
`~/.local/share/dotfiles/agents`. This repository owns the agent setup; it does
not depend on the dotfiles checkout.

## Quick Start

Prerequisites: Bun 1.3+, curl, Git, npm, and npx. Linux also needs Bash,
Python 3.11+, and a systemd user manager. Arch systems need `yay` when
`ai-memory` is absent. macOS needs Homebrew; apply installs Homebrew Bash,
Python, and Google Chrome when they are absent.

```sh
./apply.sh
./test.sh
```

`apply.sh` installs OpenCode V2, converts the global configuration to the native
V2 schema, installs compatible plugins and skills, and manages ai-memory.
Set `OPENCODE_SERVER_ENABLED=true` only on the M4. Read
[`opencode/V2-MIGRATION.md`](opencode/V2-MIGRATION.md) before cutover.

## Components

| Component | Documentation |
| --- | --- |
| OpenCode runtime | [opencode/README.md](opencode/README.md) |
| OpenCode plugins | [plugins/README.md](plugins/README.md) |
| OpenCode MCP servers | [mcps/README.md](mcps/README.md) |
| ai-memory service | [ai-memory/README.md](ai-memory/README.md) |
| ai-jail policy | [ai-jail/README.md](ai-jail/README.md) |
| Bash entry point | [shell/README.md](shell/README.md) |
| Skills | [skills/README.md](skills/README.md) |
| Shared helper | [lib/README.md](lib/README.md) |
| Agent policy | [AGENTS.md](AGENTS.md) |

`skills.tsv` is the skill inventory. Run `./test.sh --repo-only` for the
deterministic checks without changing the workstation.
