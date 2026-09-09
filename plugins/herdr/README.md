# Herdr OpenCode Integration

Herdr 0.9.0 owns these upstream-generated files:

```text
~/.config/opencode/plugins/herdr-agent-state.js
~/.config/opencode/herdr-tui-session.js
```

It also owns only the `./herdr-tui-session.js` plugin entry in
`~/.config/opencode/tui.jsonc`. Its bundled OpenCode integration version is 11.
Use `herdr integration install opencode` and `herdr integration status` to write
and check these files. Do not edit the generated payloads.

The agent-stack installer keeps the theme and Learn registration in
`~/.config/opencode/tui.json`. OpenCode loads `tui.json` before `tui.jsonc` and
combines the plugin sources. Keep both files.

The lifecycle plugin reports the pane identity and agent state. The TUI plugin
reports the selected native OpenCode session. Both remain inactive unless the
process has the Herdr pane environment.

See [`../../herdr/README.md`](../../herdr/README.md) for installation, machine
profiles, workstreams, daily use, and restart recovery.
