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
| `zoom-out` | `mattpocock/skills@engineering/zoom-out` | Zoom out for broader context or higher-level perspective. |
| `plannotator-review` | Plannotator installer | Review uncommitted changes or PRs. |
| `plannotator-annotate` | Plannotator installer | Annotate markdown files, folders, or URLs. |
| `plannotator-last` | Plannotator installer | Annotate the agent's last message. |
| `plannotator-compound` | Plannotator installer (extras) | Analyze plan archive for denial patterns and produce an HTML dashboard report. |
| `plannotator-setup-goal` | Plannotator installer (extras) | Turn an idea into a goal package through structured discovery and Plannotator review. |
| `plannotator-visual-explainer` | Plannotator installer (extras) | Generate self-contained HTML visualizations with Plannotator theming. |
| `tdd` | `mattpocock/skills@engineering/tdd` | Red-green-refactor implementation workflow. |
| `teach` | `mattpocock/skills@productivity/teach` | Teach a concept, workflow, tool, or codebase area. |
| `writing-great-skills` | `mattpocock/skills@productivity/writing-great-skills` | Author new agent skills with proper structure and progressive disclosure. |

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