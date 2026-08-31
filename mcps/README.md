# OpenCode MCP Servers

`apply.sh` merges the following MCP entries into
`~/.config/opencode/opencode.json`:

| Server group | Entries | Authentication | Documentation |
| --- | --- | --- | --- |
| GitHub | `github` | Machine-local PAT file | [github/README.md](github/README.md) |
| Linear | `linear` | OpenCode OAuth | [linear/README.md](linear/README.md) |
| Cloudflare | `cloudflare-api`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability` | OpenCode OAuth | [cloudflare/README.md](cloudflare/README.md) |
| ai-memory | `ai-memory` | Local loopback service | [../ai-memory/README.md](../ai-memory/README.md) |

The GitHub, Linear, and Cloudflare entries are remote servers. The ai-memory
entry is local and is managed together with its native service and lifecycle
integration.

Use `opencode mcp list` to inspect the configured entries. Add future MCP
documentation under `mcps/<name>/README.md` and link it from this index.
