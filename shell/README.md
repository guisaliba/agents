# Shell Entry Point

`opencode.bash` contains the marked block that `apply.sh` merges into
`~/.bash_aliases`. The merge preserves unrelated aliases and functions. Reload
the file after apply:

```sh
source ~/.bash_aliases
```

## Commands

| Command | Behavior |
| --- | --- |
| `opencode` | Starts or resumes `ai-memory run opencode`. |
| `opencode -c` | Lets OpenCode select its latest native session. |
| `opencode --session <id>` | Opens and links the selected session. |
| `opencode-raw ...` | Runs native OpenCode for diagnostics and recovery. |

The functions are not exported. This prevents recursion when ai-memory starts
the native OpenCode executable. Automation should call `ai-memory run opencode`
explicitly. Use `ai-memory run --fresh opencode` to replace the native session
while keeping the same workstream.

The wrapper rejects unjailed `--yolo` and `--auto` starts. Use the explicit
ai-jail flow in [`../ai-jail/README.md`](../ai-jail/README.md) for dangerous
mode.
