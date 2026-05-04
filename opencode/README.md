
# OpenCode

OpenCode uses:

* global instructions: `~/.config/opencode/AGENTS.md` and `~/.opencode/AGENTS.md`
* shared skills: `~/.agents/skills`

Managed integrations:

* caveman via `npx skills add JuliusBrussee/caveman -a opencode`
* cavemem via `cavemem install --ide opencode`
* rtk via `rtk init -g --agent opencode`

OpenCode should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
