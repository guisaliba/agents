# Shell Entry Point

`opencode.bash` contains the marked block that `apply.sh` merges into
`~/.bash_aliases`. The merge preserves unrelated aliases and functions. Reload
the file after apply:

```sh
source ~/.bash_aliases
```

On macOS, apply adds one managed block to `~/.bash_profile`. This block sources
`~/.bash_aliases` for the Homebrew Bash login shells that Herdr starts. Apply
does not change the account login shell from zsh.

## Commands

| Command | Behavior |
| --- | --- |
| `opencode` | Starts or resumes `ai-memory run opencode`; in a Herdr pane it gives only that child `HERDR_AGENT=opencode`. |
| `opencode -c` | Lets OpenCode select its latest native session. |
| `opencode --session <id>` | Opens and links the selected session. |
| `opencode-raw ...` | Runs native OpenCode for diagnostics and recovery. |

The functions are not exported. This prevents recursion when ai-memory starts
the native OpenCode executable. Automation should call `ai-memory run opencode`
explicitly. Use `ai-memory run --fresh opencode` to replace the native session
while keeping the same workstream.

In Herdr automation, use `HERDR_AGENT=opencode ai-memory run opencode`. The
pane keeps its inherited `HERDR_ENV`, `HERDR_PANE_ID`, and `HERDR_SOCKET_PATH`.
The wrapper does not export `HERDR_AGENT` to the interactive shell. Use named
workstreams and separate Git worktrees for concurrent OpenCode tasks as
described in [`../herdr/README.md`](../herdr/README.md).

The wrapper rejects unjailed `--yolo` and `--auto` starts. Use the explicit
ai-jail flow in [`../ai-jail/README.md`](../ai-jail/README.md) for dangerous
mode.
