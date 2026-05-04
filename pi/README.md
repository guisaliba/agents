
# Pi

Pi uses:

* global instructions: `~/.pi/agent/AGENTS.md`
* shared skills: `~/.agents/skills`
* global extensions: `~/.pi/agent/extensions/`

Managed integrations:

* caveman through `pi-caveman`
* rtk through a Pi extension that rewrites bash tool commands with `rtk rewrite`
* cavemem through a Pi extension bridge that exposes custom tools backed by `cavemem mcp`

## Cavemem bridge

Pi does not currently use cavemem through a documented native MCP client configuration in this setup.

Instead, `~/.pi/agent/extensions/cavemem-bridge/` registers Pi custom tools:

* `cavemem_search`
* `cavemem_list_sessions`
* `cavemem_timeline`
* `cavemem_get_observations`

The bridge calls cavemem's MCP stdio server and keeps cavemem as the storage/source-of-truth layer.
