# OpenCode

OpenCode uses:

* global instructions: `~/.config/opencode/AGENTS.md`
* runtime config: `~/.config/opencode/opencode.json`, tracked at `chezmoi/dot_config/opencode/opencode.json`
* commands: `~/.config/opencode/commands/`, tracked at `chezmoi/dot_config/opencode/commands/`
* shared skills: `~/.agents/skills`

Managed integrations:

* rtk via `rtk init -g --opencode`
* plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`

OpenCode also reads `~/.agents/skills`, so shared skills stay in the same source tree used by Codex and Pi.

OpenCode should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
