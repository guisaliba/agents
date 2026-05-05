# Skills

Shared skills are installed into:

```text
~/.agents/skills
```

## Architecture

This directory is documentation only. Do not vendor skill payloads under `agents/skills/`.

Managed skill payloads live in the chezmoi source tree:

```text
chezmoi/dot_agents/skills/<skill-name>/
```

Chezmoi materializes those files to:

```text
~/.agents/skills/<skill-name>/
```

Pi also has a Pi-local skill target for skills installed by the Skills CLI with `-a pi`:

```text
~/.pi/agent/skills/<skill-name>/
```

Those Pi-local managed skills are tracked under:

```text
chezmoi/dot_pi/agent/skills/<skill-name>/
```

## Skill visibility across agents

Codex, OpenCode, and Pi all read the shared `~/.agents/skills` path in this setup, so a skill copied there is available to all three harnesses after their next reload/start, assuming the harness supports shared skill discovery.

Agent-specific `npx skills add ... -a <agent>` commands may also write harness-specific metadata or locations. Use them when the Skills CLI supports the target agent and you want that agent's native installer behavior.

For replication to other machines, commit the skill payload under `chezmoi/dot_agents/skills/` and, if Pi needs a Pi-local copy, under `chezmoi/dot_pi/agent/skills/`.

## Managed skills

| Skill | Source | Purpose |
| --- | --- | --- |
| `caveman` | `JuliusBrussee/caveman@caveman` | Concise agent output and token-efficient communication. |
| `find-skills` | local dotfiles skill tracked at `chezmoi/dot_agents/skills/find-skills` | Discover and install skills from the open agent skills ecosystem. |
| `grill-me` | `mattpocock/skills@productivity/grill-me` | Requirement discovery. |
| `grill-with-docs` | `mattpocock/skills@engineering/grill-with-docs` | Requirement discovery grounded in repo docs. |
| `tdd` | `mattpocock/skills@engineering/tdd` | Red-green-refactor implementation workflow. |

## Installing skills

Preferred global install pattern:

```sh
npx -y skills add <owner/repo> -g -a <agent> -s <skill-name> -y --copy
```

Examples:

```sh
npx -y skills add JuliusBrussee/caveman -g -a codex -s caveman -y --copy
npx -y skills add JuliusBrussee/caveman -g -a opencode -s caveman -y --copy
```

Useful commands:

```sh
npx -y skills find <query>
npx -y skills add <owner/repo> -g -s <skill-name> -y --copy
npx -y skills ls -g
npx -y skills update -g
npx -y skills remove <skill-name> -g -y
```

After installing or updating a managed skill, copy the resulting shared skill directory into `chezmoi/dot_agents/skills/` so it is replicated on other machines.

The global AGENTS instructions expect agents to use these skills for requirement discovery, concise output, skill discovery, and TDD-oriented implementation.
