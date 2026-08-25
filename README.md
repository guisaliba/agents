# Agents

This folder contains OpenCode agent setup configuration.

## Files

- `AGENTS.md`: canonical global instructions used by OpenCode.
- `apply.sh`: installs and configures OpenCode, its TUI, ai-memory, the managed Bash entry point, model routing, OpenCode Learn, RTK, Plannotator, required skills, and the remote MCP servers. It reports whether the optional ai-jail command is available but does not install it.
- `test.sh`: deterministic local checks for harness wiring.
- `lib/agent_stack.py`: shared safe file, environment-assignment, and skill-manifest primitives used by the scripts.
- `skills.tsv`: data-only inventory of local, direct-upstream, and generated skill provenance.
- `opencode/README.md`: OpenCode-specific notes.
- `skills/README.md`: shared skills notes.
- `../bash/.bash_aliases`: canonical marked Bash function block for the managed `opencode` command and its `opencode-raw` escape hatch.

`skills.tsv` does not vendor skill payloads. The `local` rows identify the two tracked skill exceptions copied by `apply.sh`; `upstream` rows identify skills fetched individually; `ai-memory`, `plannotator`, and `cloudflare` rows identify outputs owned by their existing dedicated installers. The test script uses the same inventory to validate installed directories and the selected `SKILL.md` files.

## Runtime Wiring

### OpenCode Model Routing

The global routing policy is:

```text
Primary:
  build -> GPT-5.6 Sol (openai/gpt-5.6-sol)
  plan  -> GPT-5.6 Sol (openai/gpt-5.6-sol)

Subagents:
  general -> DeepSeek V4 Flash (opencode-go/deepseek-v4-flash)
  explore -> DeepSeek V4 Flash (opencode-go/deepseek-v4-flash)
  scout   -> DeepSeek V4 Flash when OpenCode exposes native Scout
```

`general` keeps its normal built-in write, command, implementation, refactoring, debugging, and test capabilities. No custom agent or extra permission restriction is part of this policy. When a subagent changes the workspace, the primary agent must inspect the changes and run applicable verification before final acceptance. The complete rule is in `agents/AGENTS.md`.

`agents/apply.sh` merges the managed routing fields into `~/.config/opencode/opencode.json`. The global model selects Sol for `build`, and a direct agent override pins `plan` to Sol. The merge preserves unrelated root fields, agent entries, agent-specific fields, plugins, MCP servers, permissions, providers, and commands. If an existing runtime file has invalid JSON, a non-object root, an invalid managed agent object, or a non-object `mcp` field, apply stops without overwriting the file.

Scout availability currently differs between OpenCode documentation and released/runtime implementations. Apply checks a clean OpenCode agent list. If OpenCode exposes native `scout (subagent)`, apply pins it to DeepSeek. If it does not, apply removes only this repository's prior Scout model override and does not create a custom or unrestricted fallback. `agents/test.sh` verifies the same boundary, so another supported device reports its effective Scout capability.

The script copies the complete canonical `agents/AGENTS.md` to `~/.config/opencode/AGENTS.md`. The source and deployed file must match exactly after apply.

### OpenCode Learn

Apply installs the OpenCode-only learning system from `github:guisaliba/opencode-learn#main`. It merges the configured server entry into `~/.config/opencode/opencode.json` and the TUI entry into `~/.config/opencode/tui.json`. Both entries are required for graded quiz dialogs and immediate feedback. Each merge removes stale entries for the same package, keeps one managed entry, preserves unrelated valid settings, and is idempotent.

The `learn` primary agent inherits the current session model. Apply pins `learn-researcher` to `opencode-go/deepseek-v4-flash` and pins the SVG and Mermaid maker agents to `opencode-go/deepseek-v4-flash-vision-exp`. These are OpenCode session routes. They are separate from the managed ai-memory service profile below.

Use `/learn <goal>` for frontier probing, a reviewed dependency plan, one-node teaching loops, graded quizzes, an optional live Markdown log, and inspected SVG or Mermaid teaching visuals. Mermaid rendering also needs Chrome or Chromium. The plugin can use `CHROME_PATH`, a standard system path, or a browser that Puppeteer already manages.

Matt Pocock's separate `teach` skill remains available for persistent teaching workspaces with source lists, HTML lessons, reference pages, and learning records. Apply removes the retired `learn-profile`, `learn-verify`, `learn-visual`, and `probe` skill directories before it installs the canonical Matt Pocock `teach` source.

### ai-memory Continuity

ai-memory adds memory to OpenCode at three levels:

| Level | Installed part | Result |
| --- | --- | --- |
| Search and durable pages | `mcp.ai-memory` at `http://127.0.0.1:49374/mcp` | OpenCode can search recent observations, the wiki, handoffs, and durable pages. |
| Automatic lifecycle capture | generated `~/.config/opencode/plugins/ai-memory.ts` | OpenCode sends bounded and sanitized session and tool events. It can inject a pending handoff at session start. |
| Managed workstream | interactive Bash `opencode` → `ai-memory run opencode` | ai-memory links one native OpenCode session to a portable workstream, resumes it, and imports its visible transcript records after exit. |

The native per-user service stores its private state under `~/.local/share/ai-memory`. Its config is `~/.config/ai-memory/config.toml`. Its optional secrets file is `~/.config/ai-memory/env`. Apply creates the layout, keeps both config files private, writes `~/.config/systemd/user/ai-memory.service` with the resolved native executable path, and enables the service. The test script verifies the unit and local loopback endpoint.

This opinionated setup uses an unauthenticated loopback service. Apply fails before it changes OpenCode configuration when `AI_MEMORY_AUTH_TOKEN`, `AI_MEMORY_AUTH__BEARER_TOKEN`, or `AI_MEMORY_AUTH__ACTOR_PROXY_BEARER_TOKEN` is active in the shell, systemd user manager, or environment file. It also rejects `[auth].bearer_token` and `[auth].actor_proxy_bearer_token` in `config.toml`. Do not set those values with this design. They would require authenticated MCP, hook, managed-launcher, and jail wiring that this setup intentionally does not generate.

`dotfiles` owns the service policy, the exact MCP entry, and the `instructions` reference in `opencode.json`. The current ai-memory binary generates and owns these files:

- `~/.config/opencode/plugins/ai-memory.ts`
- `~/.config/opencode/ai-memory.md`
- `~/.agents/skills/ai-memory-*`

The generated instruction file is separate from `~/.config/opencode/AGENTS.md`. OpenCode loads the global AGENTS file automatically and loads the generated file through its global `instructions` array. This keeps the canonical tracked `agents/AGENTS.md` byte-for-byte equal to its deployed copy and lets each installed ai-memory release refresh its own routing text.

Apply passes the managed config path and `http://127.0.0.1:49374` explicitly to the hook generator. A stale default config or client `AI_MEMORY_SERVER_URL` cannot redirect the generated OpenCode plugin.

Apply uses `--project-strategy repo-root` for the generated plugin. A session keeps one project identity when it changes into a repository subdirectory. Add a project `.ai-memory.toml` only when that project needs an explicit override.

#### Model Routing

ai-memory treats GPT-5.6 Sol, DeepSeek V4 Flash, Kimi K3, GPT-5.6 Luna, GLM-5.3, and other OpenCode Go choices as models inside the same OpenCode harness. A model change needs no ai-memory adapter or config change. OpenCode continues to own provider authentication, agent routing, and the selected model.

The managed ledger records OpenCode as the harness. It does not promise a complete recursive copy of every child-subagent transcript. It imports visible records from the linked native session, including completed tool results that are present in that session. It excludes hidden reasoning and unsupported private records.

#### Managed-By-Default Bash Entry Point

Apply takes the canonical marked block from `bash/.bash_aliases` and merges only that block into `~/.bash_aliases`. It preserves unrelated aliases and functions. Open a new Bash shell or run `source ~/.bash_aliases` after apply.

The block defines an unexported Bash function. It changes normal interactive commands as follows:

| Typed command | Effective command | Result |
| --- | --- | --- |
| `opencode` | `ai-memory run opencode` | Starts or resumes the linked managed workstream. |
| `opencode -c` | `ai-memory run opencode -c` | Makes OpenCode choose its latest native session and relinks the workstream to it. |
| `opencode --session <id>` | `ai-memory run opencode --session <id>` | Opens that native session and links it to the workstream. |
| `opencode session list` | `ai-memory run opencode session list` | Runs the utility command after the launcher prepares the current workstream. |
| `opencode-raw ...` | native `opencode ...` | Diagnostic and recovery escape; lifecycle MCP/hooks still load, but no managed visible-event ledger is imported. |

The function is not exported. When ai-memory starts its child, it resolves the real OpenCode executable from `PATH`, so it cannot recurse into the parent Bash function. An executable shim named `opencode` would need brittle executable pinning to avoid that recursion and is intentionally not used.

On the first managed start, ai-memory can offer recent OpenCode sessions from the same checkout for one-time adoption. Verify the title and ID. After the link exists, routine use is plain `opencode`; ai-memory resumes that exact session with OpenCode's native `--session <id>` option.

Native selectors override ai-memory’s automatic resume target, but do not bypass the managed launcher: ai-memory does not inject its linked selector when `-c`, `--continue`, `--session`, or `--fork` is present. The native session selected by OpenCode then becomes linked to the managed workstream.

This override covers normal interactive Bash command words. It cannot intercept an absolute executable path, `command opencode`, `env opencode`, a noninteractive script that did not source the function, or `opencode` passed as an argument to another executable. Use explicit `ai-memory run opencode` in automation. `opencode-raw` keeps one supported bypass for diagnostics and recovery, not routine sessions.

To create a new native OpenCode session and keep the same portable workstream, use:

```sh
ai-memory run --fresh opencode
```

The new session receives a bounded unseen delta. The full visible ledger stays searchable with `ai-memory workstream-search`, and the durable wiki stays available through MCP. ai-memory does not put every old raw token into the new context. To start an independent line of work, use `--new <name>` instead of `--fresh`.

#### Managed ai-memory LLM

The OpenCode session model and the ai-memory service model are independent. ai-memory does not inherit the current TUI model, the primary-agent model, or a subagent model. A session can move between Sol, Luna, Kimi, DeepSeek, or GLM without changing its memory identity. The separate ai-memory service uses one provider and model for consolidation, review, and optional reranking across all sessions.

This repository manages a persistent profile selector in `~/.config/ai-memory/env`. The default is `DOTFILES_AI_MEMORY_LLM_PROFILE=opencode-go-deepseek`.

| Profile | Provider and model | Activation |
| --- | --- | --- |
| `opencode-go-deepseek` | `opencode` / `deepseek-v4-flash` | Default. `OPENCODE_API_KEY` is non-empty in the environment file. |
| `openai-subscription-luna` | `openai-oauth` / `gpt-5.6-luna` | A valid OpenAI OAuth entry exists in `~/.local/share/ai-memory/auth.json`. |
| `openai-api-luna` | `openai` / `gpt-5.6-luna` | `OPENAI_API_KEY` is non-empty in the environment file. This uses Platform API billing. |
| `disabled` | No provider or model | Always stays in zero-LLM mode. |

(These are just the author's preferred models at the time of this setup wiring, 2026-08-17. Available through paid subscriptions, OpenCode Go and OpenAI's ChatGPT Pro.)

Apply preserves user-owned keys and unrelated values. It manages the profile, provider, model, `AI_MEMORY_AUTO_IMPROVE__REQUIRE_APPROVAL=true`, and `AI_MEMORY_AUTO_IMPROVE__SCHEDULER__ENABLED=false`. If the selected credential is absent, it writes an empty provider so the service starts safely in zero-LLM mode. If the ai-memory OAuth file or OpenAI entry is malformed, apply fails before it rewrites the environment policy.

The default OpenCode Go flow is:

```sh
./agents/apply.sh
# Edit ~/.config/ai-memory/env and add:
# OPENCODE_API_KEY=<your OpenCode Go API key>
./agents/apply.sh
./agents/test.sh
```

Use an API key from the OpenCode Go account that supplies DeepSeek V4 Flash. ai-memory calls the OpenCode Go API directly. It does not run this service job inside the OpenCode TUI, and it does not inherit the TUI login, selected model, or model effort. Do not put the key in Git.

For the optional OpenAI subscription profile, set `DOTFILES_AI_MEMORY_LLM_PROFILE=openai-subscription-luna`, run `ai-memory --data-dir "$HOME/.local/share/ai-memory" --config "$HOME/.config/ai-memory/config.toml" auth login openai-oauth`, and rerun apply. This login is owned by ai-memory. It does not inherit or copy OpenCode's OpenAI login. It can use the same ChatGPT/Codex subscription account, but it stores a separate refresh token in the ai-memory data directory.

To change profiles, edit only `DOTFILES_AI_MEMORY_LLM_PROFILE` in `~/.config/ai-memory/env`, add the selected profile's key when required, and rerun apply. Do not edit `config.toml` to select the provider or model; the managed environment policy wins.

Current endpoint compatibility limits the available choices:

| Candidate | Works with ai-memory 1.28.0 | Reason |
| --- | --- | --- |
| DeepSeek V4 Flash through OpenCode Go | Yes; managed default | OpenCode Go exposes `deepseek-v4-flash` at `/chat/completions`, which matches ai-memory's OpenCode provider. |
| GPT-5.6 Luna through OpenAI subscription OAuth | Yes; selectable profile | ai-memory uses its own ChatGPT/Codex OAuth token and Codex Responses backend. |
| Qwen3.8 Max through OpenCode Go | No | OpenCode Go exposes `qwen3.8-max` at `/messages`, but ai-memory's OpenCode provider calls `/chat/completions`. |
| GPT-5.6 Luna through OpenCode Go | No | OpenCode Go exposes Luna at `/responses`, not `/chat/completions`. |
| GPT-5.6 Luna through the OpenAI API | Yes; selectable profile | It needs `OPENAI_API_KEY` and uses Platform API billing. |

The compatibility table follows the [current OpenCode Go endpoint table](https://opencode.ai/docs/go/), the [pinned ai-memory OpenCode provider](https://github.com/akitaonrails/ai-memory/blob/7f052990991aa541022a4bd015b58d1f5a9e8bf5/crates/ai-memory-llm/src/opencode.rs), the [pinned provider-neutral request fields](https://github.com/akitaonrails/ai-memory/blob/7f052990991aa541022a4bd015b58d1f5a9e8bf5/crates/ai-memory-llm/src/types.rs), and the [OpenAI GPT-5.6 Luna model reference](https://developers.openai.com/api/docs/models/gpt-5.6-luna).

OpenCode Go's current catalog exposes `low`, `high`, and `max` for DeepSeek V4 Flash, and DeepSeek documents `high` as the API default. However, ai-memory 1.28.0 does not expose or send a reasoning-effort field through its OpenCode provider. This setup therefore cannot pin `max`; it omits the field and receives the provider default, which is currently `high`. Do not add an unrecognized effort variable to the environment file. An explicit `max` policy requires upstream ai-memory support for the request field. See the [OpenCode Go model record](https://github.com/anomalyco/models.dev/blob/dev/providers/opencode-go/models/deepseek-v4-flash.toml) and [DeepSeek Chat Completions reference](https://api-docs.deepseek.com/api/create-chat-completion/).

### ai-jail For Managed Dangerous Mode

ai-jail is optional and is not a dependency of ai-memory or the normal managed OpenCode runtime. Apply does not install or configure it. Install it separately only when this sandboxed dangerous-mode path is required.

ai-memory translates its `--yolo` option to OpenCode's native `--auto`. It does not create a sandbox. ai-jail must be the outer process, and the harness must be explicit:

```sh
ai-jail ai-memory run opencode --yolo
```

The interactive function rejects `opencode --yolo` and native `opencode --auto` so dangerous mode cannot look jailed when it is not. `ai-jail opencode --yolo` also bypasses the function because `opencode` is an argument to ai-jail, not the Bash command word. Use the full explicit form above.

Current ai-jail can detect this command and apply both its `ai-memory` and `opencode` command policies. It cannot know that bare `ai-memory run` will later select OpenCode, and its narrow parser does not identify OpenCode when `--yolo` is before the harness. The fully configured jail command and its capability risks are in `agents/opencode/README.md`.

### GitHub MCP

Apply manages the official remote GitHub MCP Server as the global `mcp.github` entry. It uses `https://api.githubcopilot.com/mcp/` and the server-side `X-MCP-Toolsets` allow-list `context,repos,issues,pull_requests,actions`. These toolsets cover the authenticated user context, repositories and content, issues, pull requests and reviews, and GitHub Actions. The limited set avoids the tool-schema cost of `all`. It does not enable read-only mode, so supported writes remain available when the token permits them. The `context` toolset supplies current-user context; the larger `users` toolset is not enabled.

Authentication is machine-specific. OpenCode reads a dedicated PAT from `~/.config/opencode/secrets/github-mcp-pat` through its documented `{file:...}` interpolation. Apply creates an empty `0600` placeholder when the file is absent and never replaces its contents. The token is not stored in this repository or copied into the runtime JSON. Apply and the deterministic test suite do not require a live token, network access, or a GitHub response.

After apply, write only the PAT to the protected file. Do not include quotes or the `Bearer` prefix. The detailed setup command is in `agents/opencode/README.md`.

Restart OpenCode after apply or any GitHub MCP token-file change. Then inspect the connection with:

```sh
opencode mcp list
opencode mcp debug github
```

If the server reports `401 Unauthorized`, check that the token file is non-empty, contains only a valid PAT, and grants access to the required repositories and operations. If tools are missing, confirm the managed allow-list and restart OpenCode. `opencode mcp auth github` is not used because the managed PAT configuration sets `oauth` to `false`.

Use GitHub MCP for GitHub platform objects and hosted state. Use local `git` for worktree and Git graph operations. Use `gh` when MCP coverage is insufficient, when local checkout integration is necessary, for Actions logs or artifacts that MCP does not expose adequately, or for `gh api`. File edits in a checked-out repository stay in the local diff and normal Git workflow. The detailed operating notes are in `agents/opencode/README.md`, and the agent selection rule is in `agents/AGENTS.md`.

### RTK

RTK is installed as the shell/tool-output compaction layer.

- OpenCode: command rewrite plugin installed at `~/.config/opencode/plugins/rtk.ts`.

Useful commands:

```sh
rtk rewrite "git status --short"
rtk gain
rtk <command>
```

### Plannotator

Plannotator is installed as the plan review and code review layer.

- Binary: installed automatically when missing via the official installer.
- OpenCode: plugin `@plannotator/opencode@latest` in `~/.config/opencode/opencode.json`. Commands at `~/.config/opencode/commands/plannotator-*`.
- Shared skills: `plannotator-compound`, `plannotator-setup-goal`, `plannotator-visual-explainer` at `~/.agents/skills/`.

Useful commands:

```sh
plannotator review [pr-url]
plannotator annotate <file|url|folder>
plannotator last
```

## Apply

From the repo root:

```sh
./agents/apply.sh
./agents/test.sh
```

For a repository-only check that does not require an applied workstation:

```sh
./agents/test.sh --repo-only
```

Prerequisites are Bash, `curl`, `git`, `npm`, `npx`, Python 3.11 or newer, and a working systemd user manager. When ai-memory is absent, apply also needs `yay` and installs the native `ai-memory-bin` AUR package. The script requires a native Linux ai-memory executable at version 1.28.0 or newer. It rejects the upstream Docker wrapper before it changes OpenCode configuration. ai-jail is optional and must be installed separately when sandboxed dangerous-mode sessions are required. Chrome or Chromium is required for `/learn` Mermaid visuals. On a new machine, authenticate the providers that supply `openai/gpt-5.6-sol`, `opencode-go/deepseek-v4-flash`, and `opencode-go/deepseek-v4-flash-vision-exp` with `opencode-raw auth login` before use. Also put a separate OpenCode Go API key in `~/.config/ai-memory/env` to enable the default ai-memory service model. Model policy is stored in Git. Provider API keys, OAuth tokens, session credentials, the ai-memory token pepper, and memory data are not.

The automatic installation target is Omarchy or another Arch-based system. It also works in an Arch-based WSL2 distribution when systemd user services are enabled. On another WSL2 distribution, install a current native ai-memory binary before apply; apply writes its matching user unit. Use the upstream Docker-wrapper design only as a separate setup. Do not mix a Docker wrapper and the native user service on the same `127.0.0.1:49374` endpoint or data layout.

The script installs OpenCode if missing, installs the native ai-memory AUR tool if needed, copies `AGENTS.md`, merges global routing and integrations, adds the OpenCode Learn server and TUI plugins, initializes and starts ai-memory, merges the canonical marked function block into `~/.bash_aliases`, refreshes the generated ai-memory plugin and skills, configures RTK, installs Plannotator, and installs required skills. It converges the selected ai-memory LLM profile and keeps zero-LLM mode until that profile's credential is ready. Upstream skills are installed live and tracked local skills are copied on every run. The Cloudflare skills bundle (`https://github.com/cloudflare/skills`) is installed as a group without `-s` so every upstream skill is pulled in. The Cloudflare, GitHub, Linear, and ai-memory remote MCP entries are merged into `~/.config/opencode/opencode.json`. Use `opencode mcp auth <name>` for the OAuth-enabled Cloudflare and Linear servers. GitHub uses the dedicated machine-local PAT file. ai-memory uses the local loopback service without bearer authentication.

For an ai-memory upgrade, first create a backup outside the repository. Then update the package and rerun apply. Apply refreshes the generated OpenCode plugin, routing instructions, and skills for the installed version.

```sh
ai-memory --data-dir "$HOME/.local/share/ai-memory" \
  backup --to "$HOME/ai-memory-backup.tar.gz"
yay -S ai-memory-bin
./agents/apply.sh
./agents/test.sh
```

## Policy

Global OpenCode configuration is the default source of user-wide model and agent policy. Use `~/.config/opencode/opencode.json` for normal work. Add a project-level `opencode.json` only when that project has an explicit technical requirement for different settings. OpenCode's normal project-over-global precedence remains available for that exception.

OpenCode instruction arrays are replaced, not concatenated, when a higher-precedence project config defines them. If an exceptional project-level `opencode.json` has an `instructions` array, include `~/.config/opencode/ai-memory.md` in that project array too.

Do not vendor upstream skill, generated ai-memory instruction, or plugin payloads in this repo.

Default rule: install live, do not track copies.

Exceptions: `find-skills` and `auto-pr-review` are local tracked skills under `agents/skills/`. `agents/apply.sh` copies them to `~/.agents/skills/` on every setup run.
