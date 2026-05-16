
# OpenCode

OpenCode uses:

* global instructions: `~/.config/opencode/AGENTS.md`
* runtime config: `~/.config/opencode/opencode.json`, tracked at `chezmoi/dot_config/opencode/opencode.json`
* shared skills: `~/.agents/skills`

Managed integrations:

* caveman via `npx skills add JuliusBrussee/caveman -g -a opencode -s caveman -y --copy`
* caveman autostart via native OpenCode plugin at `~/.config/opencode/plugins/caveman/`
* cavemem via `cavemem install --ide opencode`
* rtk via `rtk init -g --opencode`

OpenCode should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
