# Learn

OpenCode Learn is a plugin, not a global skill. It provides `/learn` with
prior-knowledge probing, dependency plans, one-node lessons, graded quizzes,
Markdown logs, and inspected SVG or Mermaid visuals.

## Managed Checkout

`apply.sh` clones or fast-forwards `https://github.com/guisaliba/learn.git` on
`main` into:

```text
~/.local/share/opencode/learn
```

The managed checkout is separate from the development checkout at
`~/projects/active/self/learn`. It must be clean and use the expected remote
and branch. Dependencies use `bun install --frozen-lockfile`.

The plugin is registered in both `~/.config/opencode/opencode.json` and
`~/.config/opencode/tui.json`. Both entries are required for the server and
TUI quiz flows.

## Requirements

OpenCode must be at least `1.18.22` and Bun must be at least `1.3`. Apply sets
`PUPPETEER_SKIP_DOWNLOAD=true`; Mermaid rendering uses Chrome or Chromium
already installed on the system. Set `CHROME_PATH` when it is not in a
standard location.

Matt Pocock's `/teach` workflow is separate. It creates persistent teaching
workspaces and does not replace `/learn`.
