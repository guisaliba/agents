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
- generated ai-memory instructions: `~/.config/opencode/ai-memory.md`
- generated ai-memory lifecycle plugin: `~/.config/opencode/plugins/ai-memory.ts`
- commands: `~/.config/opencode/commands/`
- shared skills: `~/.agents/skills`

`agents/apply.sh` is the deployment source of truth. It copies the complete `agents/AGENTS.md` to the global instruction path. It merges the global model, explicit Plan model, default agent, available built-in subagent models, Plannotator plugin, and managed MCP servers into the runtime JSON while it preserves unrelated valid configuration and existing agent-specific fields. Invalid JSON, a non-object root, an invalid managed agent object, or a non-object `mcp` field causes a safe failure without overwrite.

Managed integrations:

- rtk via `rtk init -g --opencode`
- plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`
- official GitHub MCP Server via the managed global `mcp.github` entry
- ai-memory via the managed global `mcp.ai-memory` entry and the upstream-generated plugin

OpenCode reads `~/.agents/skills/*/SKILL.md` for global skill discovery.

## ai-memory

The managed MCP entry is:

```json
{
  "mcp": {
    "ai-memory": {
      "type": "remote",
      "url": "http://127.0.0.1:49374/mcp",
      "enabled": true
    }
  },
  "instructions": [
    "~/.config/opencode/ai-memory.md"
  ]
}
```

`agents/apply.sh` owns this JSON shape. It preserves other instruction paths and keeps exactly one ai-memory path. The installed ai-memory binary owns the generated instruction file, lifecycle plugin, and its five Agent Skills. Do not edit these generated files by hand.

Apply runs the equivalent of:

```sh
ai-memory \
  --data-dir "$HOME/.local/share/ai-memory" \
  --config "$HOME/.config/ai-memory/config.toml" \
  install-hooks \
  --agent opencode \
  --server-url http://127.0.0.1:49374 \
  --project-strategy repo-root \
  --apply

ai-memory install-instructions \
  --target "$HOME/.config/opencode/ai-memory.md" \
  --no-skills

ai-memory install-skills \
  --scope global \
  --agent agents
```

Restart OpenCode after apply. Then verify the service and MCP connection:

```sh
ai-memory status --json
opencode mcp list
opencode mcp debug ai-memory
```

### Models And Subagents

ai-memory integrates with the OpenCode harness, not with one session model. The fixed Sol and DeepSeek routes in this repository and manual switches to Kimi, Luna, GLM, or another OpenCode Go model use the same capture and workstream integration.

The internal ai-memory LLM is separate. It never inherits the model, model effort, or credentials selected in an OpenCode session. The default profile uses `opencode` plus `deepseek-v4-flash` after a separate `OPENCODE_API_KEY` is put in the ai-memory environment file. The profile and alternative provider procedures are in `agents/README.md`.

The managed OpenCode importer follows the linked native session ID. It does not promise to recursively import each child-subagent session. A completed subtask result that is visible in the linked parent session can enter the ledger. Hidden reasoning and model metadata do not enter the portable ledger.

### Direct Sessions And Managed Workstreams

The two start paths have different contracts:

| Command | Native OpenCode resume | Lifecycle memory | Portable visible-event ledger |
| --- | --- | --- | --- |
| `opencode` or `opencode -c` | OpenCode owns it | Yes | No |
| `ai-memory run opencode` | ai-memory resumes the linked OpenCode session | Yes | Yes |

Direct OpenCode sessions remain fully supported. The MCP server, generated lifecycle plugin, wiki, and pending handoffs remain available. Direct mode sends bounded, best-effort lifecycle observations. Managed mode also reads the linked OpenCode SQLite transcript after exit and imports visible incremental message, tool, and compaction records.

For normal managed continuation, use:

```sh
ai-memory run opencode
```

On the first managed start for a checkout, ai-memory can offer up to eight recent same-checkout OpenCode sessions for adoption. Review the title and session ID. After adoption, plain managed start resumes the linked ID.

OpenCode native selectors stay authoritative:

```sh
ai-memory run opencode -c
ai-memory run opencode --session <id>
ai-memory run opencode --session <id> --fork
```

ai-memory does not add its linked `--session` selector when one of these options is present. `-c` tells OpenCode to select its latest session and can relink the workstream to a different session. It is an override, not the routine managed-resume command.

For a session list, use the native command:

```sh
opencode session list
```

`ai-memory run opencode session list` is passed through as an OpenCode utility command, but the outer launcher still prepares a workstream first. It gives no benefit for a list-only operation. After you select an ID, adopt it with `ai-memory run opencode --session <id>`.

To replace the linked native session but retain the same portable workstream, use:

```sh
ai-memory run --fresh opencode
```

The new session gets a bounded unseen delta. It can search the full visible ledger and wiki. It does not receive the full raw history in its prompt. The old OpenCode session is still in OpenCode and can still be opened directly. `--new <name>` has a different purpose: it starts an independent workstream.

For a bounded project briefing at the start of each direct or managed session, opt in per repository with `.ai-memory.toml`:

```toml
[briefing]
inject_on_session_start = true
max_chars = 4000
```

This package contains pinned pages, project rules, slots, and recent titles. It still does not contain all old transcripts. This repository does not enable it globally because it uses context on every session start.

### `--yolo` And ai-jail

ai-memory owns the dangerous-mode translation:

```text
ai-memory --yolo -> opencode --auto
```

This translation is built in. It is not a sandbox. Use ai-jail as the outer process, put the explicit harness before `--yolo`, and keep the ai-memory server state outside the jail.

One fully explicit start is:

```sh
mkdir -p "$HOME/.local/share/ai-memory-client"

ai-jail \
  --network \
  --agent-state \
  --map "$HOME/.agents/skills" \
  --map "$HOME/.local/bin" \
  --rw-map "$HOME/.local/share/ai-memory-client" \
  ai-memory \
    --data-dir "$HOME/.local/share/ai-memory-client" \
    run opencode --yolo
```

The separate client directory persists the managed launcher's local checkout registry. It does not mount the real server database and wiki at `~/.local/share/ai-memory` into the yolo process. The local service remains outside the jail and is reached through loopback. This is a filesystem boundary only. Because the jail has network access and this setup uses an unauthenticated loopback service, the jailed process can query and change live memory through MCP. It can also exfiltrate memory that it retrieves.

For the shorter command, add this policy to the trusted and machine-local `~/.ai-jail` file after review:

```toml
[commands.ai-memory]
rw_maps = ["~/.local/share/ai-memory-client"]
ro_maps = ["~/.agents/skills", "~/.local/bin"]

[commands.opencode]
network = true
agent_state = true
```

Then run:

```sh
mkdir -p "$HOME/.local/share/ai-memory-client"
ai-jail ai-memory \
  --data-dir "$HOME/.local/share/ai-memory-client" \
  run opencode --yolo
```

This repository installs ai-jail but does not write `~/.ai-jail`. The policy grants capabilities that need a direct decision:

- `network = true` gives all sandbox processes unrestricted outbound network access. OpenCode Go and the local loopback MCP service need network access.
- `agent_state = true` mounts `~/.config/opencode` and `~/.local/share/opencode` read-write. This exposes provider credentials, the GitHub MCP PAT file, config, plugins, and the session database to all sandbox processes.
- `--yolo` removes OpenCode's normal approval step for actions that are not explicitly denied.
- ai-jail reduces host access. It is not a disposable virtual machine or a malware-analysis boundary.

Current ai-jail detects the explicit `ai-memory run opencode` shape and layers its `commands.ai-memory` policy, then its `commands.opencode` policy. It cannot apply OpenCode-specific policy to `ai-jail ai-memory run` because ai-memory selects the harness only after the jail is built. It also fails closed to outer ai-memory policy when `--yolo` comes before `opencode`. Therefore, do not use these forms for the configured jail path:

```sh
ai-jail ai-memory run --yolo opencode
ai-jail ai-memory run --yolo
```

ai-memory has managed adapters only for the harnesses in its current support matrix. A future harness is not automatically supported only because it has MCP. Current ai-jail recognizes an even smaller set of managed wrapper harnesses for command-specific state. Review both support matrices before a future harness switch.

### Data And Provider Boundaries

ai-memory data is protected by local file permissions but is not encrypted at rest by ai-memory. Managed mode copies more visible project content than direct lifecycle mode. Capture sanitization and `ignore_paths` are best-effort controls, not data-loss prevention. Shell commands and free-text quotations can bypass path-based exclusions.

Without credentials for the selected profile, the integration uses no ai-memory LLM provider. When credentials are ready, captured project content can leave the machine for that provider during consolidation, review, and optional reranking. Apply disables scheduled auto-improvement and requires approval for validated proposals. These safeguards do not stop explicit LLM operations.

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
        "Authorization": "Bearer {file:~/.config/opencode/secrets/github-mcp-pat}",
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

Create a dedicated PAT for GitHub MCP with only the repository access and permissions that the agent needs. Keep this token separate from the broader token used by `gh`.

The [official GitHub OpenCode guide](https://github.com/github/github-mcp-server/blob/main/docs/installation-guides/install-opencode.md) shows environment-variable interpolation for the PAT. This setup uses [OpenCode's documented file interpolation](https://opencode.ai/docs/config/#files) instead. OpenCode replaces `{file:~/.config/opencode/secrets/github-mcp-pat}` with the trimmed file contents before it parses the configuration. The resulting request still uses the required `Authorization: Bearer <PAT>` header.

Apply creates `~/.config/opencode/secrets/github-mcp-pat` as an empty `0600` file when it is absent. It never replaces an existing file or token. Write only the PAT to this file. Do not include quotes or the `Bearer` prefix. After apply, use this hidden prompt so the PAT does not enter shell history:

```sh
read -r -s -p 'GitHub MCP PAT: ' github_mcp_pat
printf '\n'
printf '%s\n' "$github_mcp_pat" >"$HOME/.config/opencode/secrets/github-mcp-pat"
unset github_mcp_pat
chmod 600 "$HOME/.config/opencode/secrets/github-mcp-pat"
```

The token file is machine-specific and is never copied into Git or `opencode.json`. The runtime JSON contains only the `{file:...}` reference. Apply and deterministic tests work with the empty placeholder and do not require GitHub access.

Restart OpenCode after apply or after you change the token file. Then verify the server with:

```sh
opencode mcp list
opencode mcp debug github
```

The debug command tests the connection and reports authentication details. `opencode mcp auth github` does not apply to this managed entry because `oauth` is `false` and the server uses the PAT header.

For `401 Unauthorized`, confirm that the token file is non-empty, contains only the current PAT, and grants the required repository access and permissions. Do not print the token during diagnosis. For a failed server, use `opencode mcp debug github`. For missing tools, inspect the `X-MCP-Toolsets` value, confirm that `enabled` is `true`, and restart OpenCode. An offline machine or an unavailable GitHub service can make the live connection fail, but it does not affect the deterministic configuration checks.

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
