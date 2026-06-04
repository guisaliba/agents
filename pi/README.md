
# Pi

Pi uses:

* global instructions: `~/.pi/agent/AGENTS.md`
* shared skills: `~/.agents/skills`
* global extensions: `~/.pi/agent/extensions/`, sourced from `agents/pi/extensions/` and `chezmoi/dot_pi/agent/extensions/`

Managed integrations:

* caveman through `pi-caveman`
* caveman autostart through `~/.pi/agent/extensions/caveman-autostart`
* rtk through a Pi extension that rewrites bash tool commands with `rtk rewrite`
* cavemem through a Pi extension bridge that exposes custom tools backed by `cavemem mcp`
* plannotator through `npm:@plannotator/pi-extension` package for plan review and code review

## Cavemem bridge

Pi does not currently use cavemem through a documented native MCP client configuration in this setup.

Instead, `~/.pi/agent/extensions/cavemem-bridge/` registers Pi custom tools:

* `cavemem_search`
* `cavemem_list_sessions`
* `cavemem_timeline`
* `cavemem_get_observations`

The bridge source lives in `agents/pi/extensions/cavemem-bridge/` and is materialized by chezmoi to `~/.pi/agent/extensions/cavemem-bridge/`.

The bridge calls cavemem's MCP stdio server and keeps cavemem as the storage/source-of-truth layer.
