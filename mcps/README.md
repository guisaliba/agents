# OpenCode MCP Servers

`apply.sh` merges the following MCP entries into
`~/.config/opencode/opencode.json`:

| Server group | Entries | Authentication | Documentation |
| --- | --- | --- | --- |
| GitHub | `github` | Machine-local PAT file | [github/README.md](github/README.md) |
| Linear | `linear` | OpenCode OAuth | [linear/README.md](linear/README.md) |
| Cloudflare | `cloudflare-api`, `cloudflare-docs`, `cloudflare-bindings`, `cloudflare-builds`, `cloudflare-observability` | OpenCode OAuth | [cloudflare/README.md](cloudflare/README.md) |
| ai-memory | `ai-memory` | Local service by default; bearer token for an explicit remote URL | [../ai-memory/README.md](../ai-memory/README.md) |

GitHub, Linear and Cloudflare use remote servers. ai-memory uses the local
service by default on every host. Set `AI_MEMORY_SERVER_URL` to a non-loopback
URL only when this host must use a remote ai-memory service.

Use `opencode mcp list` to inspect the configured entries. Add future MCP
documentation under `mcps/<name>/README.md` and link it from this index.
