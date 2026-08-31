# Agents

Standalone OpenCode agent stack for Linux workstations.

The dotfiles installer clones this repository into
`~/.local/share/dotfiles/agents`. This repository owns the agent setup; it does
not depend on the dotfiles checkout.

## Quick Start

Prerequisites: Bash, Bun 1.3+, curl, Git, npm, npx, Python 3.11+, and a
systemd user manager. Arch systems also need `yay` when `ai-memory` is absent.

```sh
./apply.sh
./test.sh
```

`apply.sh` changes global OpenCode configuration, installs live skills and
plugins, updates Learn, and manages the native ai-memory service. Read the
component documentation before applying it.

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
