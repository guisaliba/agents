# OpenCode

## Routing

```text
Primary:
  build -> GPT-5.6 Sol (openai/gpt-5.6-sol)
  plan  -> GPT-5.6 Sol (openai/gpt-5.6-sol)

Subagents:
  general -> DeepSeek V4 Flash (opencode-go/deepseek-v4-flash)
  explore -> DeepSeek V4 Flash (opencode-go/deepseek-v4-flash)
  scout   -> DeepSeek V4 Flash when OpenCode exposes native Scout
```

`general` keeps its normal built-in write and command capabilities. No custom agent or capability restriction is used. The primary agent must review the actual changes from delegated implementation, check integration points, and run applicable verification before final acceptance. This rule is in the canonical `agents/AGENTS.md`.

Apply checks Scout against a clean OpenCode agent list. It adds the fixed DeepSeek model override only for native `scout (subagent)`. If native Scout is unavailable, it leaves Scout absent instead of creating an `all` agent. This makes platform or release differences visible in `agents/test.sh` without a custom fallback.

## Ownership

OpenCode uses these global paths:

- global instructions: `~/.config/opencode/AGENTS.md`
- runtime config: `~/.config/opencode/opencode.json`
- commands: `~/.config/opencode/commands/`
- shared skills: `~/.agents/skills`

`agents/apply.sh` is the deployment source of truth. It copies the complete `agents/AGENTS.md` to the global instruction path. It merges the global model, explicit Plan model, default agent, available built-in subagent models, Plannotator plugin, and managed MCP servers into the runtime JSON while it preserves unrelated valid configuration and existing agent-specific fields. Invalid JSON, a non-object root, or an invalid managed agent object causes a safe failure without overwrite.

Managed integrations:

- rtk via `rtk init -g --opencode`
- plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`

OpenCode reads `~/.agents/skills/*/SKILL.md` for global skill discovery.

## Apply And Verify

```sh
opencode auth login
./agents/apply.sh
./agents/test.sh
```

Provider authentication is machine-specific and required for the configured models. API keys, OAuth tokens, and session credentials are not stored in this repository.

Global OpenCode configuration is the default source of user-wide model and agent policy. Use a project-level `opencode.json` only when that project has an explicit technical requirement for a different setting. OpenCode can still override global fields at project scope.

After a config change, restart OpenCode because an active process does not reload configuration.
