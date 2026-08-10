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

`agents/apply.sh` is the deployment source of truth. It copies the complete `agents/AGENTS.md` to the global instruction path. It merges the global model, explicit Plan model, default agent, available built-in subagent models, Plannotator plugin, and managed MCP servers into the runtime JSON while it preserves unrelated valid configuration and existing agent-specific fields. Invalid JSON, a non-object root, an invalid managed agent object, or a non-object `mcp` field causes a safe failure without overwrite.

Managed integrations:

- rtk via `rtk init -g --opencode`
- plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`
- official GitHub MCP Server via the managed global `mcp.github` entry

OpenCode reads `~/.agents/skills/*/SKILL.md` for global skill discovery.

## GitHub MCP

The managed configuration is:

```json
{
  "mcp": {
    "github": {
      "type": "remote",
      "url": "https://api.githubcopilot.com/mcp/",
      "enabled": true,
      "oauth": false,
      "headers": {
        "Authorization": "Bearer {env:GITHUB_PERSONAL_ACCESS_TOKEN}",
        "X-MCP-Toolsets": "context,repos,issues,pull_requests,actions"
      }
    }
  }
}
```

The remote server avoids a Docker or vendored-server dependency. The five server-side toolsets are the smallest practical set for normal engineering work in this setup:

- `context`: authenticated GitHub user and operating context.
- `repos`: repository metadata, content, commits, branches, and hosted repository searches.
- `issues`: issue reads and supported issue writes.
- `pull_requests`: pull requests, reviews, review comments, and supported writes.
- `actions`: GitHub Actions and CI state and supported workflow operations.

The allow-list reduces tool-schema context. It does not use `all`, the separate `users` toolset, or GitHub MCP read-only mode. `context` already supplies current-user context. Available writes depend on the permissions of the configured token.

### Authentication And Verification

Provide `GITHUB_PERSONAL_ACCESS_TOKEN` through the machine-specific environment that starts OpenCode. Do not put its value in this repository or in `opencode.json`. The tracked setup stores only OpenCode's `{env:GITHUB_PERSONAL_ACCESS_TOKEN}` reference. Apply and deterministic tests work when the variable is absent.

After apply, restart OpenCode so that the active process reads the new configuration and environment. Verify the server with:

```sh
opencode mcp list
opencode mcp debug github
```

The debug command tests the connection and reports authentication details. `opencode mcp auth github` does not apply to this managed entry because `oauth` is `false` and the server uses the PAT header.

For `401 Unauthorized`, confirm that the variable is available to the OpenCode process, the token is current, and its repository permissions allow the requested access. For a failed server, use `opencode mcp debug github`. For missing tools, inspect the `X-MCP-Toolsets` value, confirm that `enabled` is `true`, and restart OpenCode. An offline machine or an unavailable GitHub service can make the live connection fail, but it does not affect the deterministic configuration checks.

### Tool Selection

Use GitHub MCP for GitHub platform operations when an applicable tool exists. Examples include repository metadata, issues, pull requests, review state and comments, hosted searches, Actions state, and supported platform writes.

Use normal `git` for local status, diffs, branches, staging, commits, rebases, merges, worktrees, and other local graph or worktree operations. When files must change in an existing checkout, edit and validate them locally. Do not bypass the local diff with GitHub MCP content writes.

Keep `gh` for operations that MCP does not expose or does not represent well, local checkout integration, Actions logs and artifacts that need more detail, and arbitrary REST or GraphQL calls through `gh api`.

## Apply And Verify

```sh
opencode auth login
./agents/apply.sh
./agents/test.sh
```

Provider authentication is machine-specific and required for the configured models. API keys, OAuth tokens, and session credentials are not stored in this repository.

Global OpenCode configuration is the default source of user-wide model and agent policy. Use a project-level `opencode.json` only when that project has an explicit technical requirement for a different setting. OpenCode can still override global fields at project scope.

After a config change, restart OpenCode because an active process does not reload configuration.
