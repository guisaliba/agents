# ai-jail

ai-jail is an optional OS-level sandbox for dangerous OpenCode sessions. It
is separate from ai-memory and is not installed or configured by `apply.sh`.
This repository does not write `~/.ai-jail`.

## Explicit Start

Keep ai-jail outside ai-memory and use the full harness name:

```sh
mkdir -p "$HOME/.local/share/ai-memory-client"

ai-jail \
  --network \
  --agent-state \
  --map "$HOME/.agents/skills" \
  --map "$HOME/.local/bin" \
  --rw-map "$HOME/.local/share/ai-memory-client" \
  ai-memory \
    --data-dir "$HOME/.local/share/ai-memory-client" \
    run opencode --yolo
```

The client directory stores launcher state. It is not the server database.
The live ai-memory service remains outside the jail.

## Risks

`--network` permits outbound access. `--agent-state` exposes OpenCode config,
plugins, sessions, and provider credentials to the jailed process. `--yolo`
removes OpenCode's normal approval step. Review each capability before use.

Do not use `ai-jail opencode --yolo`, `ai-jail ai-memory run --yolo`, or
`ai-jail ai-memory run --yolo opencode` for this setup. The first bypasses the
managed launcher; the other forms prevent complete command-policy matching.
