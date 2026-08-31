# Cloudflare MCP

`apply.sh` configures five remote Cloudflare MCP servers:

| Name | Endpoint |
| --- | --- |
| `cloudflare-api` | `https://mcp.cloudflare.com/mcp` |
| `cloudflare-docs` | `https://docs.mcp.cloudflare.com/mcp` |
| `cloudflare-bindings` | `https://bindings.mcp.cloudflare.com/mcp` |
| `cloudflare-builds` | `https://builds.mcp.cloudflare.com/mcp` |
| `cloudflare-observability` | `https://observability.mcp.cloudflare.com/mcp` |

All five entries are enabled. Authenticate each server that you use with
OpenCode OAuth:

```sh
opencode mcp auth cloudflare-api
opencode mcp auth cloudflare-docs
opencode mcp auth cloudflare-bindings
opencode mcp auth cloudflare-builds
opencode mcp auth cloudflare-observability
```

Verify the configured entries with:

```sh
opencode mcp list
opencode mcp debug cloudflare-api
```

The Cloudflare skill bundle is separate from these MCP servers. It is installed
from `https://github.com/cloudflare/skills`; see [`../../skills/README.md`](../../skills/README.md).
