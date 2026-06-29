# OpenCode

OpenCode uses:

- global instructions: `~/.config/opencode/AGENTS.md`
- runtime config: `~/.config/opencode/opencode.json`
- commands: `~/.config/opencode/commands/`
- shared skills: `~/.agents/skills`

Managed integrations:

- rtk via `rtk init -g --opencode`
- plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`

OpenCode reads `~/.agents/skills/*/SKILL.md` for global skill discovery.

OpenCode should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.