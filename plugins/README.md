# OpenCode Plugins

`apply.sh` installs or configures these OpenCode plugins. Plugin payloads are
not vendored here unless the component explicitly owns a tracked exception.

| Plugin | Runtime location | Documentation |
| --- | --- | --- |
| Learn | `~/.local/share/opencode/learn` | [learn/README.md](learn/README.md) |
| Plannotator | `~/.config/opencode/opencode.json` | [plannotator/README.md](plannotator/README.md) |
| RTK | `~/.config/opencode/plugins/rtk.ts` | [rtk/README.md](rtk/README.md) |

ai-memory also generates an OpenCode lifecycle plugin. It remains documented
at [`../ai-memory/README.md`](../ai-memory/README.md) because it owns a native
service, MCP server, hooks, workstreams, instructions, and skills in addition
to the plugin.

Add future OpenCode plugin documentation under `plugins/<name>/README.md` and
link it from this index.
