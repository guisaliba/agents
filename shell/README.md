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
| `opencode` | Connects to `OPENCODE_SERVER_URL` when configured; otherwise starts `ai-memory run opencode`. |
| `opencode-local` | Forces the local fallback runtime. |
| `opencode -c` | Lets OpenCode select its latest native session. |
| `opencode --session <id>` | Opens and links the selected session. |
| `opencode-raw ...` | Runs native OpenCode for diagnostics and recovery. |

The functions are not exported. This prevents recursion when ai-memory starts
the native OpenCode executable. Automation should call `ai-memory run opencode`
explicitly. Use `ai-memory run --fresh opencode` to replace the native session
while keeping the same workstream.

Remote connection settings live in `~/.config/opencode/server.env`, mode
`0600`. `--dir` names a path on the M4 when the client uses the remote server.

Use named workstreams and separate Git worktrees for concurrent OpenCode tasks.

The wrapper rejects unjailed `--yolo` and `--auto` starts. Use the explicit
ai-jail flow in [`../ai-jail/README.md`](../ai-jail/README.md) for dangerous
mode.
