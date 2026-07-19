# Skills

Shared skills are installed into:

```text
~/.agents/skills
```

## Architecture

Most skills are installed live from upstream sources by `agents/apply.sh`. Do not vendor skill payloads under `agents/skills/` unless the skill has no upstream source.

Local skill exceptions are tracked directly under `agents/skills/<skill-name>/`. These are manual-install only and not part of the automated setup script.

## Skill discovery

OpenCode discovers global skills from `~/.agents/skills/*/SKILL.md` automatically. No extra path config is needed.

## Managed skills

Skills installed live by `agents/apply.sh`:

| Skill | Source | Purpose |
| --- | --- | --- |
| `caveman` | `JuliusBrussee/caveman@caveman` | Opt-in concise agent output and token-efficient communication. |
| `find-skills` | local at `agents/skills/find-skills` | Discover and install skills from the open agent skills ecosystem. |
| `grill-me` | `mattpocock/skills@productivity/grill-me` | Requirement discovery. |
| `grill-with-docs` | `mattpocock/skills@engineering/grill-with-docs` | Requirement discovery grounded in repo docs. |
| `handoff` | `mattpocock/skills@productivity/handoff` | Compact the conversation into a handoff document for the next agent. |
| `improve` | `shadcn/improve` | Improve codebase architecture. |
| `logging-best-practices` | `boristane/agent-skills` | Wide-event (canonical log line) logging guidance for writing, reviewing, and designing logging strategy. |
| `plannotator-review` | Plannotator installer | Review uncommitted changes or PRs. |
| `plannotator-annotate` | Plannotator installer | Annotate markdown files, folders, or URLs. |
| `plannotator-last` | Plannotator installer | Annotate the agent's last message. |
| `plannotator-compound` | Plannotator installer (extras) | Analyze plan archive for denial patterns and produce an HTML dashboard report. |
| `plannotator-setup-goal` | Plannotator installer (extras) | Turn an idea into a goal package through structured discovery and Plannotator review. |
| `plannotator-visual-explainer` | Plannotator installer (extras) | Generate self-contained HTML visualizations with Plannotator theming. |
| `tdd` | `mattpocock/skills@engineering/tdd` | Red-green-refactor implementation workflow. |
| `teach` | `mattpocock/skills@productivity/teach` | Teach a concept, workflow, tool, or codebase area. |
| `writing-great-skills` | `mattpocock/skills@productivity/writing-great-skills` | Author new agent skills with proper structure and progressive disclosure. |

### Cloudflare skills

The Cloudflare skills bundle is installed live as a group from `https://github.com/cloudflare/skills` by `agents/apply.sh`. It is added without `-s` so every skill in the upstream `skills/` directory is installed. Do not track copies of these skills under `agents/skills/`; update them by re-running `apply.sh`.

| Skill | Purpose |
| --- | --- |
| `cloudflare` | Comprehensive platform skill covering Workers, Pages, storage (KV, D1, R2), AI, networking, security, and IaC. |
| `agents-sdk` | Building stateful AI agents with state, scheduling, RPC, MCP servers, email, and streaming chat. |
| `durable-objects` | Stateful coordination, RPC, SQLite, alarms, and WebSockets. |
| `sandbox-sdk` | Secure code execution for AI code runners, interpreters, CI/CD, and interactive dev environments. |
| `wrangler` | Deploying and managing Workers, KV, R2, D1, Vectorize, Queues, and Workflows. |
| `web-perf` | Auditing Core Web Vitals and render-blocking resources. |
| `workers-best-practices` | Best practices for building on Cloudflare Workers. |
| `turnstile-spin` | Integrating Cloudflare Turnstile for bot protection. |
| `cloudflare-email-service` | Email routing and processing on Cloudflare. |
| `cloudflare-one` | Cloudflare One deployments across Access, Gateway, WARP, Tunnel, Magic WAN, DLP, CASB, posture, and identity. |
| `cloudflare-one-migrations` | Migration assessments and rollout plans for SASE migrations to Cloudflare One. |

### Cloudflare MCP servers

`agents/apply.sh` also merges the Cloudflare remote MCP servers from `https://github.com/cloudflare/skills` into the `mcp` block of `~/.config/opencode/opencode.json`. These are remote MCP endpoints (OpenCode `type: "remote"`), not skills, and authenticate via OAuth on first use.

| Server | URL | Purpose |
| --- | --- | --- |
| `cloudflare-api` | `https://mcp.cloudflare.com/mcp` | Manage account resources, zones, and settings. |
| `cloudflare-docs` | `https://docs.mcp.cloudflare.com/mcp` | Up-to-date Cloudflare docs and reference. |
| `cloudflare-bindings` | `https://bindings.mcp.cloudflare.com/mcp` | Build Workers apps with storage, AI, and compute primitives. |
| `cloudflare-builds` | `https://builds.mcp.cloudflare.com/mcp` | Manage and get insights into Workers builds. |
| `cloudflare-observability` | `https://observability.mcp.cloudflare.com/mcp` | Debug and analyze logs and analytics. |

Authenticate a server with `opencode mcp auth <name>`; list status with `opencode mcp list`.

Local-only skills (manual install):

| Skill | Source | Purpose |
| --- | --- | --- |
| `auto-pr-review` | local at `agents/skills/auto-pr-review` | Work the post-open PR review loop: read unresolved reviewer comments, judge accept/reject, fix the valid ones, reply and resolve each thread citing the commit, then @-mention the reviewer for a re-review. |

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

The global AGENTS instructions expect agents to use these skills for requirement discovery, concise output, skill discovery, and TDD-oriented implementation.
