# Codex

Codex uses:

* global instructions: `~/.codex/AGENTS.md`
* runtime config: `~/.codex/config.toml`, tracked at `chezmoi/dot_codex/config.toml`
* session hooks: `~/.codex/hooks.json`, tracked at `chezmoi/dot_codex/hooks.json.tmpl`
* shared skills: `~/.agents/skills`
* codex skills: `~/.codex/skills`

Managed integrations:

* rtk via `rtk init -g --codex`
* plannotator via `Stop` hook and command skills at `~/.codex/skills/plannotator-*`

Codex should follow the shared workflow in `agents/AGENTS.md`: clarify, plan, use TDD, verify, commit atomically when asked.
