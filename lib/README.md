# Shared Helpers

`apply.sh` sources four Bash libraries:

| File | Owns |
| --- | --- |
| `common.bash` | Logging, platform prerequisites, version checks, AUR install. |
| `ai-memory.bash` | Native ai-memory install, per-host service, environment policy, and the Claude Code wiring. |
| `rtk.bash` | RTK CLI install and the RTK hook for one Claude Code configuration directory. |
| `claude.bash` | Claude Code install, the main profile, the pstack plugin, the OpenCode Go worker profile, skills, and the Bash entry points. |

`agent_stack.py` is the standard-library-only helper used by `apply.sh`,
`test.sh`, and `bin/go-key`. It centralizes safe file writes, environment
assignment handling, skill-manifest validation, marked-block merges
(`merge-block`, `remove-block`), and JSON settings merges (`merge-json`) that
keep keys other installers own.

The helper does not run external commands and is not installed into the
workstation. Validate it through:

```sh
./test.sh --repo-only
python3 -m py_compile lib/agent_stack.py
```
