
# Pi

Pi uses:

* global instructions: `~/.pi/agent/AGENTS.md`
* shared skills: `~/.agents/skills`
* global extensions: `~/.pi/agent/extensions/`, sourced from `agents/pi/extensions/` and `chezmoi/dot_pi/agent/extensions/`

Managed integrations:

* rtk through a Pi extension that rewrites bash tool commands with `rtk rewrite`
* plannotator through `npm:@plannotator/pi-extension` package for plan review and code review
