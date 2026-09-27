# Shell Entry Point

`opencode.bash` contains the marked block that `apply.sh` merges into
`~/.bash_aliases`. The merge preserves unrelated aliases and functions. Reload
the file after apply:

```sh
source ~/.bash_aliases
```

On macOS, apply adds one managed block to `~/.bash_profile`. This block sources
`~/.bash_aliases` for Homebrew Bash login shells. Apply does not change the
account login shell from zsh.

## Commands

| Command | Behavior |
| --- | --- |
| `opencode` | Starts `ai-memory run opencode2` in the current directory. Always managed. |
| `opencode -c` | Continues the latest native session in that same workstream. |
| `opencode --session <id>` | Opens and links the selected session. |
| `opencode <directory>` | Starts the workstream in the directory you name. |
| `opencode --new` | Creates a fresh worktree and starts the session in it. |
| `opencode-raw ...` | Runs native OpenCode for diagnostics and recovery. |

The functions are not exported. This prevents recursion when ai-memory starts
the native OpenCode executable. Automation should call `ai-memory run opencode2`
explicitly. Use `ai-memory run --fresh opencode2` to replace the native session
while keeping the same workstream.

## One Behavior

There is a single code path. `opencode` never passes a server URL to OpenCode,
and it never translates a path from one machine into a path for another. The
session runs in the current directory on the machine where you typed the
command.

A session started on a client workstation is therefore a client session. To work
on the M4, run `opencode` on the M4, over SSH for example. The OpenCode server
and its web UI stay available for a browser or a phone through Tailscale Serve,
but the shell does not drive it.

## Concurrency

`opencode --new` gives the session its own Git worktree, so two sessions in one
repository never share a working tree. It creates a branch named
`opencode/<utc-timestamp>-<pid>` and a sibling directory
`<repository>-worktrees/<utc-timestamp>-<pid>`, then starts the workstream
there. The wrapper prints both paths before it launches.

A workstream is keyed by checkout, so each worktree gets its own workstream and
two sessions never collide. All worktrees of one repository resolve to the same
ai-memory project, because `git rev-parse --git-common-dir` names the shared
repository directory. So concurrent sessions share memory and do not share a
working tree.

The work is not merged for you. A session started with `--new` commits to its own
branch, and the main checkout is unchanged until you merge. Remove the worktree
and the branch when you are done:

```sh
git worktree remove ../<repo>-worktrees/<slug>
git branch -d opencode/<slug>
git worktree prune
```

Use `opencode` without `--new` for ordinary work, so the change stays in the
current checkout and the next session sees it.

The wrapper rejects unjailed `--yolo` and `--auto` starts. Use the explicit
ai-jail flow in [`../ai-jail/README.md`](../ai-jail/README.md) for dangerous
mode.
