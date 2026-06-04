# OpenCode

OpenCode uses:

* global instructions: `~/.config/opencode/AGENTS.md`
* runtime config: `~/.config/opencode/opencode.json`, tracked at `chezmoi/dot_config/opencode/opencode.json`
* commands: `~/.config/opencode/commands/`, tracked at `chezmoi/dot_config/opencode/commands/`
* shared skills: `~/.agents/skills`

Managed integrations:

* caveman via `npx skills add JuliusBrussee/caveman -g -a opencode -s caveman -y --copy`
* caveman autostart via native OpenCode plugin at `~/.config/opencode/plugins/caveman/`
* cavemem via tracked MCP config in `opencode.json`
* rtk via `rtk init -g --opencode`
* plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`

OpenCode should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
