# ai-memory

`apply.sh` manages ai-memory as a native per-user service and connects it to
OpenCode through the loopback MCP endpoint:

```text
http://127.0.0.1:49374/mcp
```

## Ownership

The service uses:

```text
~/.local/share/ai-memory
~/.config/ai-memory/config.toml
~/.config/ai-memory/env
~/.config/systemd/user/ai-memory.service
```

The ai-memory binary owns the generated OpenCode plugin, instructions, and
five ai-memory skills. Do not edit generated files by hand. The service LLM
is independent of the OpenCode session model.

The default profile is `opencode-go-deepseek` and stays in zero-LLM mode until
`OPENCODE_API_KEY` is present in the environment file. Alternative profiles
are `openai-subscription-luna`, `openai-api-luna`, and `disabled`.

## Boundary

This setup uses unauthenticated loopback access. Apply rejects bearer-token
settings in the environment, service configuration, and `config.toml`.
Do not expose this endpoint beyond the local machine without designing
matching authentication and client wiring.

Captured content can be sent to the selected provider during explicit
consolidation, review, or reranking. Keep credentials, memory data, and the
ai-memory token pepper outside Git.

## Verify

```sh
ai-memory status --json
opencode mcp list
opencode mcp debug ai-memory
```

The managed workstream entry point is documented in
[`../shell/README.md`](../shell/README.md).
