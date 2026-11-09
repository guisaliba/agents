# Shell Entry Point

`claude.bash` contains the marked block that `apply.sh` merges into
`~/.bash_aliases`. The merge preserves unrelated aliases and functions. It also
removes the retired `dotfiles OpenCode ai-memory wrapper` block. Reload the
file after apply:

```sh
source ~/.bash_aliases
```

`apply.sh` adds one managed block to `~/.bash_profile`. That block sources
`~/.bash_aliases` and `~/.profile` for login shells. It does not load
`~/.config/ai-memory/env`, so no shell exports the provider API key.

## Commands

| Command | Behavior |
| --- | --- |
| `claude` | Starts `ai-memory run claude` in the current directory. Always managed. |
| `claude --new` | Creates a fresh worktree and starts the managed session in it. |
| `claude <subcommand>` | `plugin`, `mcp`, `update`, `doctor`, `auth`, the background-session commands, and the other CLI subcommands run the native `claude`, with no managed workstream. So do `-h`, `--help`, `-v`, and `--version`. |
| `claude <flags>` | Passes the flags to Claude Code, for example `claude --continue`. |
| `claude-raw ...` | Runs native Claude Code for diagnostics and recovery. |

The functions are not exported. ai-memory and `claude-worker` therefore start the
native `claude` executable, never this wrapper.

`claude` refuses `--dangerously-skip-permissions` and
`--permission-mode bypassPermissions`. Bypass mode alone is not a sandbox.

## Worktrees

`claude --new` creates a branch named `claude/<utc-timestamp>-<pid>` and a
sibling directory `<repository>-worktrees/<utc-timestamp>-<pid>`. All
worktrees of one repository share one ai-memory project. Remove a worktree when
you are done:

```sh
git worktree remove ../<repo>-worktrees/<slug>
git branch -d claude/<slug>
git worktree prune
```
