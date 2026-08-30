# Skills

The OpenCode agentic setup is provided by the public
[`guisaliba/agents`](https://github.com/guisaliba/agents) repository. Shared
skills are installed into:

```text
~/.agents/skills
```

## Architecture

Most skills are installed live from upstream sources by `guisaliba/agents/apply.sh`. Do not vendor skill payloads under `skills/` unless the skill has no upstream source.

The installed ai-memory binary is the source for its five managed skills. `apply.sh` runs `ai-memory install-skills --scope global --agent agents` on each apply. Do not install these five through `npx` and do not track a copy in this repository.

Local tracked skills are versioned directly under `skills/<skill-name>/`. `apply.sh` copies them to `~/.agents/skills/`; it does not fetch them from upstream.

## Skill discovery

OpenCode discovers global skills from `~/.agents/skills/*/SKILL.md` automatically. No extra path config is needed.

## Skills managed by `apply.sh`

Skills installed or copied by `apply.sh`:

| Skill | Source | Purpose |
| --- | --- | --- |
| `architecture-map` | `almendili/skills@architecture-map` | Build interactive isometric architecture maps from a codebase's measured structure and real call paths. |
| `caveman` | `JuliusBrussee/caveman@caveman` | Opt-in concise agent output and token-efficient communication. |
| `code-review` | `mattpocock/skills@engineering/code-review` | Review a change against repository standards and its source specification as separate axes. |
| `daily-tasks` | local at `skills/daily-tasks` | Plan, update, review, and safely sync private daily task files in the brain vault. |
| `find-skills` | local at `skills/find-skills` | Discover and install skills from the open agent skills ecosystem. |
| `grill-me` | `mattpocock/skills@productivity/grill-me` | Requirement discovery. |
| `grill-with-docs` | `mattpocock/skills@engineering/grill-with-docs` | Requirement discovery grounded in repo docs. |
| `handoff` | `mattpocock/skills@productivity/handoff` | Compact the conversation into a handoff document for the next agent. |
| `implement` | `mattpocock/skills@engineering/implement` | Implement work from a specification or tickets, verify it, and run a code review. |
| `improve` | `shadcn/improve` | Improve codebase architecture. |
| `logging-best-practices` | `boristane/agent-skills` | Wide-event (canonical log line) logging guidance for writing, reviewing, and designing logging strategy. |
| `ai-memory-retrieval` | installed ai-memory binary | Search and rank recent observations, wiki pages, handoffs, and workstream history. |
| `ai-memory-handoff` | installed ai-memory binary | Create, inspect, accept, and route cross-session handoffs. |
| `ai-memory-durable-pages` | installed ai-memory binary | Write explicit durable notes and global preferences with correct scope and lifetime. |
| `ai-memory-learning-maintenance` | installed ai-memory binary | Review and maintain consolidated project learning. |
| `ai-memory-routing-install` | installed ai-memory binary | Install or refresh ai-memory routing instructions and managed skills. |
| `plannotator-review` | Plannotator installer | Review uncommitted changes or PRs. |
| `plannotator-annotate` | Plannotator installer | Annotate markdown files, folders, or URLs. |
| `plannotator-last` | Plannotator installer | Annotate the agent's last message. |
| `plannotator-compound` | Plannotator installer (extras) | Analyze plan archive for denial patterns and produce an HTML dashboard report. |
| `plannotator-setup-goal` | Plannotator installer (extras) | Turn an idea into a goal package through structured discovery and Plannotator review. |
| `plannotator-visual-explainer` | Plannotator installer (extras) | Generate self-contained HTML visualizations with Plannotator theming. |
| `setup-matt-pocock-skills` | `mattpocock/skills@engineering/setup-matt-pocock-skills` | Per-repo setup for the engineering skills: issue tracker, triage labels, and domain docs. |
| `tdd` | `mattpocock/skills@engineering/tdd` | Red-green-refactor implementation workflow. |
| `teach` | `mattpocock/skills@productivity/teach` | Create a persistent teaching workspace with missions, sources, HTML lessons, reference pages, and learning records. |
| `to-tickets` | `mattpocock/skills@engineering/to-tickets` | Break a plan or spec into tracer-bullet tickets with declared blocking edges, published to the configured tracker. |
| `triage` | `mattpocock/skills@engineering/triage` | Move tracker issues through the configured triage roles and create agent-ready briefs. |
| `writing-for-agents` | `mattpocock/skills@productivity/writing-for-agents` | Write predictable skills and agent instruction documents. |

### Cloudflare skills

The Cloudflare skills bundle is installed live as a group from `https://github.com/cloudflare/skills` by `apply.sh`. It is added without `-s` so every skill in the upstream `skills/` directory is installed. Do not track copies of these skills under `skills/`; update them by re-running `apply.sh`.

| Skill | Purpose |
| --- | --- |
| `cloudflare` | Comprehensive platform skill covering Workers, Pages, storage (KV, D1, R2), AI, networking, security, and IaC. |
| `agents-sdk` | Building stateful AI agents with state, scheduling, RPC, MCP servers, email, and streaming chat. |
| `durable-objects` | Stateful coordination, RPC, SQLite, alarms, and WebSockets. |
| `sandbox-next` | Cloudflare Sandbox applications using the `@cloudflare/sandbox@next` preview package. |
| `sandbox-stable` | Cloudflare Sandbox applications using the stable package. |
| `sandbox-migrate-to-next` | Port Cloudflare Sandbox applications from stable to the `@next` preview package. |
| `wrangler` | Deploying and managing Workers, KV, R2, D1, Vectorize, Queues, and Workflows. |
| `web-perf` | Auditing Core Web Vitals and render-blocking resources. |
| `workers-best-practices` | Best practices for building on Cloudflare Workers. |
| `turnstile-spin` | Integrating Cloudflare Turnstile for bot protection. |
| `cloudflare-email-service` | Email routing and processing on Cloudflare. |
| `cloudflare-one` | Cloudflare One deployments across Access, Gateway, WARP, Tunnel, Magic WAN, DLP, CASB, posture, and identity. |
| `cloudflare-one-migrations` | Migration assessments and rollout plans for SASE migrations to Cloudflare One. |

### Remote MCP servers

`apply.sh` also merges the Cloudflare remote MCP servers from `https://github.com/cloudflare/skills` into the `mcp` block of `~/.config/opencode/opencode.json`. These are remote MCP endpoints (OpenCode `type: "remote"`), not skills, and authenticate via OAuth on first use.

| Server | URL | Purpose |
| --- | --- | --- |
| `cloudflare-api` | `https://mcp.cloudflare.com/mcp` | Manage account resources, zones, and settings. |
| `cloudflare-docs` | `https://docs.mcp.cloudflare.com/mcp` | Up-to-date Cloudflare docs and reference. |
| `cloudflare-bindings` | `https://bindings.mcp.cloudflare.com/mcp` | Build Workers apps with storage, AI, and compute primitives. |
| `cloudflare-builds` | `https://builds.mcp.cloudflare.com/mcp` | Manage and get insights into Workers builds. |
| `cloudflare-observability` | `https://observability.mcp.cloudflare.com/mcp` | Debug and analyze logs and analytics. |

The Linear remote MCP server is merged the same way:

| Server | URL | Purpose |
| --- | --- | --- |
| `linear` | `https://mcp.linear.app/mcp` | Find, create, and update Linear issues, projects, and comments. |

Authenticate a server with `opencode mcp auth <name>`; list status with `opencode mcp list`.

Local tracked skills (copied by `apply.sh`):

| Skill | Source | Purpose |
| --- | --- | --- |
| `auto-pr-review` | local at `skills/auto-pr-review` | Work the post-open PR review loop: read unresolved reviewer comments, judge accept/reject, fix the valid ones, reply and resolve each thread citing the commit, then @-mention the reviewer for a re-review. |
| `daily-tasks` | local at `skills/daily-tasks` | Maintain the private daily task record and publish only task files plus the parent journal gitlink. |

## Installing skills

Preferred global install pattern:

```sh
npx -y skills add <owner/repo> -g -a opencode -s <skill-name> -y --copy
```

Useful commands:

```sh
npx -y skills find <query>
npx -y skills add <owner/repo> -g -s <skill-name> -y --copy
npx -y skills ls -g
npx -y skills update -g
npx -y skills remove <skill-name> -g -y
```

`architecture-map` is installed directly from `https://github.com/almendili/skills` with `-s architecture-map`; it does not need a registry entry.

`teach` is installed from Matt Pocock's upstream source. The retired Alvar `teach`, `probe`, `learn-profile`, `learn-verify`, and `learn-visual` directories are removed before the required skills are installed. Alvar's adaptive method now lives in the separate OpenCode Learn plugin and `/learn` command documented in [`../learn/README.md`](../learn/README.md).

The global AGENTS instructions expect agents to use these skills for requirement discovery, concise output, skill discovery, TDD-oriented implementation, two-axis code review, and persistent teaching workspaces. OpenCode Learn is a plugin, not a shared skill.

The separate generated `~/.config/opencode/ai-memory.md` file tells OpenCode when to load the ai-memory skills. The lifecycle plugin captures routine bounded events automatically. Agents must not write routine memory notes after each turn. They write a durable page only when the user explicitly asks to remember or preserve information.
