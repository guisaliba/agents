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

Learn:
  learn primary        -> current session model
  learn-researcher     -> GPT-5.6 Luna (opencode-go/gpt-5.6-luna), from the learn repository defaults
  learn visual makers  -> GPT-5.6 Luna (opencode-go/gpt-5.6-luna), from the learn repository defaults
```

`general` keeps its normal built-in write and command capabilities. No custom agent or capability restriction is used. The primary agent must review the actual changes from delegated implementation, check integration points, and run applicable verification before final acceptance. This rule is in the canonical `AGENTS.md`.

Apply checks Scout against a clean OpenCode agent list. It adds the fixed DeepSeek model override only for native `scout (subagent)`. If native Scout is unavailable, it leaves Scout absent instead of creating an `all` agent. This makes platform or release differences visible in `test.sh` without a custom fallback.

## Ownership

OpenCode uses these global paths:

- global instructions: `~/.config/opencode/AGENTS.md`
- runtime config: `~/.config/opencode/opencode.json`
- TUI config: `~/.config/opencode/tui.json`
- themes: `~/.config/opencode/themes/`
- generated ai-memory instructions: `~/.config/opencode/ai-memory.md`
- generated ai-memory lifecycle plugin: `~/.config/opencode/plugins/ai-memory.ts`
- commands: `~/.config/opencode/commands/`
- shared skills: `~/.agents/skills`

`apply.sh` is the deployment source of truth. It copies the complete `AGENTS.md` to the global instruction path. It fetches the managed OpenCode Learn checkout, installs its dependencies, and merges the global model, explicit Plan model, default agent, available built-in subagent models, Plannotator plugin, OpenCode Learn server plugin, and managed MCP servers into the runtime JSON. It installs the tracked themes and sets the managed theme in `tui.json`. Both merges preserve unrelated valid configuration. Invalid JSON or invalid managed structures cause a safe failure without overwrite.

## Theme

Apply owns two theme parts:

- `tui.json`: the `"theme"` key. Apply always converges it to `lucent-orng`. Do not put a `theme` key in `opencode.json`; the current schema rejects it there.
- `~/.config/opencode/themes/*.json`: apply copies every tracked theme from `opencode/themes/`.

The tracked `lucent-orng.json` is a byte-exact copy of the upstream TUI asset at [anomalyco/opencode](https://github.com/anomalyco/opencode), path `packages/tui/src/theme/assets/lucent-orng.json`, commit `b72b50006b24666da9f2088dbce907d6b24b6901`. To refresh it, download that asset again and replace the tracked file.

A theme file with this name takes priority over the binary's built-in copy. This keeps the look stable when a future OpenCode release drops or changes the built-in theme. After an apply that changes theme files, restart OpenCode because the TUI loads configuration once at start.

Managed integrations:

- rtk via `rtk init -g --opencode`
- plannotator via plugin `@plannotator/opencode@latest` and commands at `~/.config/opencode/commands/plannotator-*`
- OpenCode Learn via the managed local checkout at `~/.local/share/opencode/learn` in both server and TUI configuration
- official GitHub MCP Server via the managed global `mcp.github` entry
- ai-memory via the managed global `mcp.ai-memory` entry and the upstream-generated plugin

OpenCode reads `~/.agents/skills/*/SKILL.md` for global skill discovery. OpenCode Learn is a plugin, not a global skill.

### Learn Checkout

Apply maintains `~/.local/share/opencode/learn` from the `main` branch of `https://github.com/guisaliba/learn.git`. It uses a fast-forward-only update and refuses a dirty checkout, a wrong remote, or a non-`main` branch. The checkout is separate from the development repository at `~/projects/active/self/learn`.

The default repository URL is public HTTPS. Set `LEARN_REPOSITORY_URL` to an SSH or other authenticated Git URL when the repository is private. Git credentials are not stored in this repository or in OpenCode configuration. OpenCode `1.18.22` or newer and Bun `1.3` or newer must be installed before apply. Learn dependencies are installed with `bun install --frozen-lockfile`.

## Learning Systems

`/learn` is the OpenCode-native adaptive workflow. It probes prior knowledge, presents a dependency plan, teaches one node at a time, grades quizzes through the TUI, can update a Markdown log, and can create inspected SVG or Mermaid visuals. The server and TUI plugin entries are both required. Mermaid rendering requires Chrome or Chromium. Apply sets `PUPPETEER_SKIP_DOWNLOAD=true` because this setup uses a system browser through `CHROME_PATH` or a standard browser path instead of downloading a second Puppeteer browser.

`/teach` is Matt Pocock's separate workspace workflow. It uses a mission, trusted resources, HTML lessons, reference pages, and learning records. It does not replace `/learn`, and `/learn` does not replace it.

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

`apply.sh` owns this JSON shape. It preserves other instruction paths and keeps exactly one ai-memory path. The installed ai-memory binary owns the generated instruction file, lifecycle plugin, and its five Agent Skills. Do not edit these generated files by hand.

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

The internal ai-memory LLM is separate. It never inherits the model, model effort, or credentials selected in an OpenCode session. The default profile uses `opencode` plus `deepseek-v4-flash` after a separate `OPENCODE_API_KEY` is put in the ai-memory environment file. The profile and alternative provider procedures are in `README.md`.

The managed OpenCode importer follows the linked native session ID. It does not promise to recursively import each child-subagent session. A completed subtask result that is visible in the linked parent session can enter the ledger. Hidden reasoning and model metadata do not enter the portable ledger.

### Managed-By-Default Interactive Sessions

The tracked `shell/opencode.bash` contains the canonical OpenCode function. Apply merges only its marked block into `~/.bash_aliases`, so it does not replace unrelated Bash customizations. Reload it after apply:

```sh
source ~/.bash_aliases
```

The function is deliberately unexported:

```bash
opencode() {
  command ai-memory run opencode "$@"
}
```

This is safer than an executable shim. ai-memory starts the native executable as a child process and cannot see the parent shell's unexported function, so there is no recursive `opencode` lookup.

Normal interactive use now has this contract:

| Command | Native OpenCode resume | Lifecycle memory | Portable visible-event ledger |
| --- | --- | --- | --- |
| `opencode` | ai-memory resumes the workstream-linked native session | Yes | Yes |
| `opencode -c` | OpenCode selects its latest native session; ai-memory relinks to it | Yes | Yes |
| `opencode --session <id>` | OpenCode selects the ID; ai-memory links it | Yes | Yes |
| `opencode session list` | Utility passthrough after workstream preparation | No session | No transcript import for the utility |
| `opencode-raw ...` | OpenCode owns it | Yes | No |

On the first managed start for a checkout, ai-memory can offer up to eight recent same-checkout OpenCode sessions for adoption. Review the title and session ID. After adoption, plain `opencode` resumes the linked ID.

OpenCode native selectors stay authoritative. ai-memory does not add its linked `--session` selector when `-c`, `--continue`, `--session`, or `--fork` is present. A selected native session becomes the new link, so use plain `opencode` for routine continuation.

`opencode session list` works through the function, but the outer launcher still prepares a workstream. Use `opencode-raw session list` only when a diagnostic must avoid even that launcher step. After selecting an ID, adopt it with `opencode --session <id>`.

The function covers normal interactive Bash command words. An absolute path, `command opencode`, `env opencode`, a script that does not source the function, or `opencode` passed as another program's argument bypasses it. Automation must call `ai-memory run opencode` explicitly. `opencode-raw` is the supported diagnostic and recovery escape, not a routine entry point.

To replace the linked native session but retain the same portable workstream, use:

```sh
ai-memory run --fresh opencode
```

The new session gets a bounded unseen delta. It can search the full visible ledger and wiki. It does not receive the full raw history in its prompt. The old OpenCode session is still in OpenCode and can still be opened with `opencode-raw --session <id>`. `--new <name>` has a different purpose: it starts an independent workstream.

For a bounded project briefing at the start of each direct or managed session, opt in per repository with `.ai-memory.toml`:

```toml
[briefing]
inject_on_session_start = true
max_chars = 4000
```

This package contains pinned pages, project rules, slots, and recent titles. It still does not contain all old transcripts. This repository does not enable it globally because it uses context on every session start.

### `--yolo` And ai-jail

ai-jail is an OS-level process sandbox, not another agent harness and not a virtual machine. On Linux it uses Bubblewrap namespaces plus Landlock, seccomp, and resource limits. The current project is writable and its changes are real. By default, the rest of `$HOME` and `/tmp` are private temporary filesystems, while network, agent credentials, broad environment inheritance, display, GPU, Docker, SSH, and the systemd user bus are unavailable. Every enabled map or capability deliberately weakens that boundary.

ai-memory owns the dangerous-mode translation:

```text
ai-memory --yolo -> opencode --auto
```

This translation is built in. It is not a sandbox. Use ai-jail as the outer process, put the explicit harness before `--yolo`, and keep the ai-memory server state outside the jail.

The Bash function rejects `opencode --yolo` and native `opencode --auto` because either expansion would be managed but not jailed. `ai-jail opencode --yolo` is also wrong for this setup: Bash does not expand a function name that is only an argument to another executable, so it bypasses ai-memory. Always keep both ai-jail and ai-memory explicit for dangerous mode.

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

This repository does not install ai-jail or write `~/.ai-jail`. Install ai-jail separately before use. The policy grants capabilities that need a direct decision:

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
./apply.sh
source ~/.bash_aliases
opencode-raw auth login
./apply.sh
./test.sh
```

The first apply installs OpenCode and the managed Bash functions. Provider authentication is machine-specific and required for the configured session models. The second apply is safe and refreshes the generated integrations after authentication. API keys, OAuth tokens, and session credentials are not stored in this repository.

Global OpenCode configuration is the default source of user-wide model and agent policy. Use a project-level `opencode.json` only when that project has an explicit technical requirement for a different setting. OpenCode can still override global fields at project scope.

After a config change, restart OpenCode because an active process does not reload configuration.
