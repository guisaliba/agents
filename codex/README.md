# Codex

Codex uses:

* global instructions: `~/.codex/AGENTS.md`
* runtime config: `~/.codex/config.toml`, tracked at `chezmoi/dot_codex/config.toml`
* MCP config: `~/.codex/config.json`, tracked at `chezmoi/dot_codex/config.json`
* session hooks: `~/.codex/hooks.json`, tracked at `chezmoi/dot_codex/hooks.json.tmpl`
* shared skills: `~/.agents/skills`
* codex skills: `~/.codex/skills`

Managed integrations:

* caveman via `npx skills add JuliusBrussee/caveman -g -a codex -s caveman -y --copy`
* caveman autostart via Codex `SessionStart` hook
* cavemem via `cavemem install --ide codex` and tracked MCP config
* rtk via `rtk init -g --codex`
* plannotator via `Stop` hook and command skills at `~/.codex/skills/plannotator-*`

Codex should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
