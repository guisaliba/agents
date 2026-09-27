# Learn

OpenCode Learn is a plugin, not a global skill. It provides `/learn` with
prior-knowledge probing, dependency plans, one-node lessons, graded quizzes,
Markdown logs, and inspected SVG or Mermaid visuals.

## V2 Status

Learn is not loaded by OpenCode V2. Its V1 server plugin and separate V1 TUI
plugin do not run through the V2 compatibility layer. A complete port must use
`@opencode/plugin`, a stable plugin ID, `setup(ctx)`, V2 transforms and hooks,
and the V2 CLI plugin API. Server-only loading is not feature parity because it
removes graded quiz dialogs.

The existing checkout remains at:

```text
~/.local/share/opencode/learn
```

The managed checkout is separate from the development checkout at
`~/projects/active/self/learn`. It must be clean and use the expected remote
and branch. Dependencies use `bun install --frozen-lockfile`.

Do not add this path to `plugins` or `cli.json` until its server tools, events,
session log updates, quiz IPC, dialogs, feedback, visuals, cleanup, and package
exports pass real V2 tests.

Matt Pocock's `/teach` workflow is separate. It creates persistent teaching
workspaces and does not replace `/learn`.
