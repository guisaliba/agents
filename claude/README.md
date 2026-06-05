# Claude Code

Claude Code uses:

* global instructions: `~/.claude/CLAUDE.md`, generated from `agents/AGENTS.md`
* runtime settings: `~/.claude/settings.json`, tracked at `chezmoi/dot_claude/settings.json`
* shared skills copied into Claude's native personal skills path: `~/.claude/skills`
* shared lifecycle hook: `~/.agents/bin/ensure-agent-stack.sh`

Managed integrations:

* caveman through `~/.claude/skills/caveman` plus `SessionStart` and `UserPromptSubmit` hooks
* cavemem through user-scope Claude MCP config: `claude mcp add -s user cavemem -- cavemem mcp`
* rtk through `~/.claude/RTK.md` and a `PreToolUse` Bash hook running `rtk hook claude`

Claude Code does not use `AGENTS.md` as its global instruction filename. The applier keeps one source of truth by rendering `agents/AGENTS.md` into `~/.claude/CLAUDE.md` through chezmoi.
