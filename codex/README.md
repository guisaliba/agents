
# Codex

Codex uses:

* global instructions: `~/.codex/AGENTS.md`
* runtime config: `~/.codex/config.toml`, tracked at `agents/codex/config.toml`
* session hooks: `~/.codex/hooks.json`, tracked at `chezmoi/dot_codex/hooks.json`
* shared skills: `~/.agents/skills`

Managed integrations:

* caveman via `npx skills add JuliusBrussee/caveman -g -a codex -s caveman -y --copy`
* caveman autostart via Codex `SessionStart` hook
* cavemem via `cavemem install --ide codex`
* rtk via `rtk init -g --codex`

Codex should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
