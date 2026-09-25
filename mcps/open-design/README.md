# OpenDesign in OpenCode

`apply.sh` registers the local OpenDesign MCP server and the checkout's
functional skills and design templates in global OpenCode configuration.
MCP is the tool connection; Agent Skills are the `SKILL.md` workflows that
OpenCode loads from the checkout. The source checkout must stay in place.

Set `OPEN_DESIGN_CHECKOUT` to the absolute checkout path before `./apply.sh`
if the checkout is not at `$HOME/open-design`. On hosts without that checkout,
apply skips this integration. Use `OPEN_DESIGN_REQUIRED=true` to make a missing
checkout an error. The launcher calls
`pnpm tools-dev start daemon --json` in that checkout and uses the returned
URL for each MCP connection. It needs Node 24, pnpm 10.33.2, and a built
daemon CLI (`pnpm --filter @open-design/daemon build` in the checkout if the
entry is missing). No web or desktop process is needed for MCP tools.

After applying, restart OpenCode and run `opencode mcp list`. Ask OpenCode to
list OpenDesign skills or projects to verify the tools. The full Studio
preview requires the web runtime: `pnpm tools-dev start web` in the checkout.
If the checkout moves, set `OPEN_DESIGN_CHECKOUT` again and rerun `./apply.sh`.
